-- image-transforms: Image upscale, enhance and style-transfer jobs (BuilderKit image_enhancer_upscaler and ghibli_generation tables) as a child of item-tracker: the input key, the result key and a free-text transform type, charged up front or recorded from an outside generator.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.itr_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.itr_valid_keys(text[], integer) from public, anon, authenticated;

create table public.itr_jobs (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  type text not null check (length(type) between 1 and 40),
  input_key text not null check (input_key ~ '^[A-Za-z0-9_./-]{1,255}$' and input_key !~ '\.\.'),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  output_keys    text[] not null default '{}' check (itr_valid_keys(output_keys, 1)),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index itr_jobs_item_subject_idx on public.itr_jobs (item_id, subject_id);
create index itr_jobs_subject_status_idx on public.itr_jobs (subject_id, status, created_at desc);
create index itr_jobs_requested_by_idx on public.itr_jobs (requested_by);

create function public.itr_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'image_transform') then
    raise exception 'itr_jobs requires an item of kind image_transform' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger itr_jobs_kind before insert on public.itr_jobs for each row execute function public.itr_check_kind();


-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.itr_request(p_subject uuid, p_type text, p_input_key text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'itr.run'), 1) into v_cost;
  v_key := 'itr:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'itr.run', 'itr_jobs', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'image_transform', left(coalesce(p_type, 'Image transform'), 200), 'itr');
  insert into public.itr_jobs (item_id, subject_id, requested_by, type, input_key, cost, charge_key)
    values (v_id, p_subject, v_user, p_type, p_input_key, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.itr_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.itr_jobs set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.itr_complete(p_item uuid, p_keys text[]) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.itr_jobs set status = 'succeeded', error = null, completed_at = now(), output_keys = coalesce(p_keys, '{}')
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.itr_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.itr_jobs%rowtype;
begin
  update public.itr_jobs set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'itr.run', 'itr_jobs', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.itr_record(p_subject uuid, p_user uuid, p_external_ref text, p_type text, p_input_key text, p_keys text[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('itr:' || p_external_ref, 0));
  select item_id into v_existing from public.itr_jobs where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'image_transform', left(coalesce(p_type, 'Image transform'), 200), 'itr');
  insert into public.itr_jobs (item_id, subject_id, requested_by, type, input_key, prediction_id, status, output_keys, cost, completed_at)
    values (v_id, p_subject, p_user, p_type, p_input_key, p_external_ref, 'succeeded', coalesce(p_keys, '{}'), 0, now());
  return v_id;
end $$;
revoke execute on function public.itr_check_kind(), public.itr_mark_started(uuid, text), public.itr_complete(uuid, text[]), public.itr_fail(uuid, text), public.itr_record(uuid, uuid, text, text, text, text[]) from public, anon, authenticated;
revoke execute on function public.itr_request(uuid, text, text) from public, anon;
grant execute on function public.itr_request(uuid, text, text) to authenticated;

alter table public.itr_jobs enable row level security;
create policy itr_jobs_select on public.itr_jobs for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.itr_jobs');
grant select on public.itr_jobs to authenticated;
