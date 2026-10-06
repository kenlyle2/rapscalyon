-- qr-code-generations: AI QR-code generation jobs (the BuilderKit qr_code_generations table) as a child of item-tracker: prompt, target URL and an image key, charged up front or recorded from an outside generator.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.qrg_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.qrg_valid_keys(text[], integer) from public, anon, authenticated;

create table public.qrg_codes (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  prompt text not null check (length(prompt) between 1 and 2000),
  url text not null check (length(url) between 1 and 2000),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  output_keys    text[] not null default '{}' check (qrg_valid_keys(output_keys, 1)),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index qrg_codes_item_subject_idx on public.qrg_codes (item_id, subject_id);
create index qrg_codes_subject_status_idx on public.qrg_codes (subject_id, status, created_at desc);
create index qrg_codes_requested_by_idx on public.qrg_codes (requested_by);

create function public.qrg_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'qr_code') then
    raise exception 'qrg_codes requires an item of kind qr_code' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger qrg_codes_kind before insert on public.qrg_codes for each row execute function public.qrg_check_kind();


-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.qrg_request(p_subject uuid, p_prompt text, p_url text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'qrg.generate'), 1) into v_cost;
  v_key := 'qrg:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'qrg.generate', 'qrg_codes', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'qr_code', left(coalesce(left(p_url, 200), 'QR code'), 200), 'qrg');
  insert into public.qrg_codes (item_id, subject_id, requested_by, prompt, url, cost, charge_key)
    values (v_id, p_subject, v_user, p_prompt, p_url, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.qrg_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.qrg_codes set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.qrg_complete(p_item uuid, p_keys text[]) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.qrg_codes set status = 'succeeded', error = null, completed_at = now(), output_keys = coalesce(p_keys, '{}')
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.qrg_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.qrg_codes%rowtype;
begin
  update public.qrg_codes set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'qrg.generate', 'qrg_codes', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.qrg_record(p_subject uuid, p_user uuid, p_external_ref text, p_prompt text, p_url text, p_keys text[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('qrg:' || p_external_ref, 0));
  select item_id into v_existing from public.qrg_codes where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'qr_code', left(coalesce(left(p_url, 200), 'QR code'), 200), 'qrg');
  insert into public.qrg_codes (item_id, subject_id, requested_by, prompt, url, prediction_id, status, output_keys, cost, completed_at)
    values (v_id, p_subject, p_user, p_prompt, p_url, p_external_ref, 'succeeded', coalesce(p_keys, '{}'), 0, now());
  return v_id;
end $$;
revoke execute on function public.qrg_check_kind(), public.qrg_mark_started(uuid, text), public.qrg_complete(uuid, text[]), public.qrg_fail(uuid, text), public.qrg_record(uuid, uuid, text, text, text, text[]) from public, anon, authenticated;
revoke execute on function public.qrg_request(uuid, text, text) from public, anon;
grant execute on function public.qrg_request(uuid, text, text) to authenticated;

alter table public.qrg_codes enable row level security;
create policy qrg_codes_select on public.qrg_codes for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.qrg_codes');
grant select on public.qrg_codes to authenticated;
