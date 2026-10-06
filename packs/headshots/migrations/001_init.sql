-- headshots: AI headshots as two children of item-tracker (BuilderKit headshot_models and headshot_generations): train a personal model from uploaded photos, then generate headshots from a finished model of the same workspace, charged up front or recorded from an outside generator.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.hsh_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.hsh_valid_keys(text[], integer) from public, anon, authenticated;

create table public.hsh_models (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  name text not null check (length(name) between 1 and 120),
  model_type text not null check (length(model_type) between 1 and 40),
  input_keys text[] not null default '{}' check (hsh_valid_keys(input_keys, 30)),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  model_ref text check (length(model_ref) between 1 and 200),
  expires_at timestamptz,
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade,
  unique (item_id, subject_id)
);
create index hsh_models_item_subject_idx on public.hsh_models (item_id, subject_id);
create index hsh_models_subject_status_idx on public.hsh_models (subject_id, status, created_at desc);
create index hsh_models_requested_by_idx on public.hsh_models (requested_by);

create function public.hsh_model_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'headshot_model') then
    raise exception 'hsh_models requires an item of kind headshot_model' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger hsh_models_kind before insert on public.hsh_models for each row execute function public.hsh_model_check_kind();


-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.hsh_model_request(p_subject uuid, p_name text, p_model_type text, p_input_keys text[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'hsh.train'), 1) into v_cost;
  v_key := 'hsh_model:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'hsh.train', 'hsh_models', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'headshot_model', left(coalesce(p_name, 'Headshot model'), 200), 'hsh');
  insert into public.hsh_models (item_id, subject_id, requested_by, name, model_type, input_keys, cost, charge_key)
    values (v_id, p_subject, v_user, p_name, p_model_type, p_input_keys, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.hsh_model_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.hsh_models set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.hsh_model_complete(p_item uuid, p_model_ref text, p_expires_at timestamptz) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.hsh_models set status = 'succeeded', error = null, completed_at = now(), model_ref = p_model_ref, expires_at = p_expires_at
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.hsh_model_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.hsh_models%rowtype;
begin
  update public.hsh_models set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'hsh.train', 'hsh_models', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.hsh_model_record(p_subject uuid, p_user uuid, p_external_ref text, p_name text, p_model_type text, p_input_keys text[], p_model_ref text, p_expires_at timestamptz) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hsh_model:' || p_external_ref, 0));
  select item_id into v_existing from public.hsh_models where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'headshot_model', left(coalesce(p_name, 'Headshot model'), 200), 'hsh');
  insert into public.hsh_models (item_id, subject_id, requested_by, name, model_type, input_keys, prediction_id, status, model_ref, expires_at, cost, completed_at)
    values (v_id, p_subject, p_user, p_name, p_model_type, p_input_keys, p_external_ref, 'succeeded', p_model_ref, p_expires_at, 0, now());
  return v_id;
end $$;
revoke execute on function public.hsh_model_check_kind(), public.hsh_model_mark_started(uuid, text), public.hsh_model_complete(uuid, text, timestamptz), public.hsh_model_fail(uuid, text), public.hsh_model_record(uuid, uuid, text, text, text, text[], text, timestamptz) from public, anon, authenticated;
revoke execute on function public.hsh_model_request(uuid, text, text, text[]) from public, anon;
grant execute on function public.hsh_model_request(uuid, text, text, text[]) to authenticated;

alter table public.hsh_models enable row level security;
create policy hsh_models_select on public.hsh_models for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.hsh_models');
grant select on public.hsh_models to authenticated;
create table public.hsh_generations (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  model_item uuid not null,
  prompt text not null check (length(prompt) between 1 and 2000),
  negative_prompt text check (length(negative_prompt) between 1 and 2000),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  output_keys    text[] not null default '{}' check (hsh_valid_keys(output_keys, 8)),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade,
  foreign key (model_item, subject_id) references public.hsh_models (item_id, subject_id) on delete restrict
);
create index hsh_generations_item_subject_idx on public.hsh_generations (item_id, subject_id);
create index hsh_generations_subject_status_idx on public.hsh_generations (subject_id, status, created_at desc);
create index hsh_generations_requested_by_idx on public.hsh_generations (requested_by);
create index hsh_generations_model_item_idx on public.hsh_generations (model_item, subject_id);

create function public.hsh_gen_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'headshot') then
    raise exception 'hsh_generations requires an item of kind headshot' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger hsh_generations_kind before insert on public.hsh_generations for each row execute function public.hsh_gen_check_kind();


-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.hsh_gen_request(p_subject uuid, p_model_item uuid, p_prompt text, p_negative_prompt text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from public.hsh_models r where r.item_id = p_model_item and r.subject_id = p_subject and r.status = 'succeeded') then
    raise exception 'model_item is not a finished item of this subject' using errcode = '23514';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'hsh.generate'), 1) into v_cost;
  v_key := 'hsh_gen:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'hsh.generate', 'hsh_generations', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'headshot', left(coalesce(left(p_prompt, 200), 'Headshot'), 200), 'hsh');
  insert into public.hsh_generations (item_id, subject_id, requested_by, model_item, prompt, negative_prompt, cost, charge_key)
    values (v_id, p_subject, v_user, p_model_item, p_prompt, p_negative_prompt, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.hsh_gen_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.hsh_generations set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.hsh_gen_complete(p_item uuid, p_keys text[]) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.hsh_generations set status = 'succeeded', error = null, completed_at = now(), output_keys = coalesce(p_keys, '{}')
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.hsh_gen_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.hsh_generations%rowtype;
begin
  update public.hsh_generations set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'hsh.generate', 'hsh_generations', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.hsh_gen_record(p_subject uuid, p_user uuid, p_external_ref text, p_model_item uuid, p_prompt text, p_negative_prompt text, p_keys text[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hsh_gen:' || p_external_ref, 0));
  select item_id into v_existing from public.hsh_generations where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  if not exists (select 1 from public.hsh_models r where r.item_id = p_model_item and r.subject_id = p_subject and r.status = 'succeeded') then
    raise exception 'model_item is not a finished item of this subject' using errcode = '23514';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'headshot', left(coalesce(left(p_prompt, 200), 'Headshot'), 200), 'hsh');
  insert into public.hsh_generations (item_id, subject_id, requested_by, model_item, prompt, negative_prompt, prediction_id, status, output_keys, cost, completed_at)
    values (v_id, p_subject, p_user, p_model_item, p_prompt, p_negative_prompt, p_external_ref, 'succeeded', coalesce(p_keys, '{}'), 0, now());
  return v_id;
end $$;
revoke execute on function public.hsh_gen_check_kind(), public.hsh_gen_mark_started(uuid, text), public.hsh_gen_complete(uuid, text[]), public.hsh_gen_fail(uuid, text), public.hsh_gen_record(uuid, uuid, text, uuid, text, text, text[]) from public, anon, authenticated;
revoke execute on function public.hsh_gen_request(uuid, uuid, text, text) from public, anon;
grant execute on function public.hsh_gen_request(uuid, uuid, text, text) to authenticated;

alter table public.hsh_generations enable row level security;
create policy hsh_generations_select on public.hsh_generations for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.hsh_generations');
grant select on public.hsh_generations to authenticated;
