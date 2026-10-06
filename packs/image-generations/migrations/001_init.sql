-- image-generations: Text-to-image generation jobs (the BuilderKit image_generations table; also the base for the Ghibli-style variant) as a child of item-tracker: prompt, settings and result keys per job, charged up front and refunded once on failure, or recorded from an outside generator.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.igen_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.igen_valid_keys(text[], integer) from public, anon, authenticated;

create table public.igen_generations (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  prompt text not null check (length(prompt) between 1 and 2000),
  negative_prompt text check (length(negative_prompt) between 1 and 2000),
  model text not null check (length(model) between 1 and 100),
  guidance numeric not null check (guidance between 0 and 50),
  inference integer not null check (inference between 1 and 200),
  no_of_outputs integer not null check (no_of_outputs between 1 and 8),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  output_keys    text[] not null default '{}' check (igen_valid_keys(output_keys, 8)),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index igen_generations_item_subject_idx on public.igen_generations (item_id, subject_id);
create index igen_generations_subject_status_idx on public.igen_generations (subject_id, status, created_at desc);
create index igen_generations_requested_by_idx on public.igen_generations (requested_by);

create function public.igen_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'image_generation') then
    raise exception 'igen_generations requires an item of kind image_generation' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger igen_generations_kind before insert on public.igen_generations for each row execute function public.igen_check_kind();


-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.igen_request(p_subject uuid, p_prompt text, p_negative_prompt text, p_model text, p_guidance numeric, p_inference integer, p_no_of_outputs integer) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'igen.generate'), 1) into v_cost;
  v_key := 'igen:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'igen.generate', 'igen_generations', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'image_generation', left(coalesce(left(p_prompt, 200), 'image'), 200), 'igen');
  insert into public.igen_generations (item_id, subject_id, requested_by, prompt, negative_prompt, model, guidance, inference, no_of_outputs, cost, charge_key)
    values (v_id, p_subject, v_user, p_prompt, p_negative_prompt, p_model, p_guidance, p_inference, p_no_of_outputs, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.igen_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.igen_generations set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.igen_complete(p_item uuid, p_keys text[]) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.igen_generations set status = 'succeeded', error = null, completed_at = now(), output_keys = coalesce(p_keys, '{}')
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.igen_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.igen_generations%rowtype;
begin
  update public.igen_generations set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'igen.generate', 'igen_generations', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.igen_record(p_subject uuid, p_user uuid, p_external_ref text, p_prompt text, p_negative_prompt text, p_model text, p_guidance numeric, p_inference integer, p_no_of_outputs integer, p_keys text[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('igen:' || p_external_ref, 0));
  select item_id into v_existing from public.igen_generations where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'image_generation', left(coalesce(left(p_prompt, 200), 'image'), 200), 'igen');
  insert into public.igen_generations (item_id, subject_id, requested_by, prompt, negative_prompt, model, guidance, inference, no_of_outputs, prediction_id, status, output_keys, cost, completed_at)
    values (v_id, p_subject, p_user, p_prompt, p_negative_prompt, p_model, p_guidance, p_inference, p_no_of_outputs, p_external_ref, 'succeeded', coalesce(p_keys, '{}'), 0, now());
  return v_id;
end $$;
revoke execute on function public.igen_check_kind(), public.igen_mark_started(uuid, text), public.igen_complete(uuid, text[]), public.igen_fail(uuid, text), public.igen_record(uuid, uuid, text, text, text, text, numeric, integer, integer, text[]) from public, anon, authenticated;
revoke execute on function public.igen_request(uuid, text, text, text, numeric, integer, integer) from public, anon;
grant execute on function public.igen_request(uuid, text, text, text, numeric, integer, integer) to authenticated;

alter table public.igen_generations enable row level security;
create policy igen_generations_select on public.igen_generations for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.igen_generations');
grant select on public.igen_generations to authenticated;
