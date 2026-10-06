-- voice-transcriptions: Voice-to-text jobs (the BuilderKit voice_transcriptions table) as a child of item-tracker: the audio key, transcript and summary, charged up front or recorded from an outside service.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.vtr_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.vtr_valid_keys(text[], integer) from public, anon, authenticated;

create table public.vtr_transcriptions (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  audio_key text not null check (audio_key ~ '^[A-Za-z0-9_./-]{1,255}$' and audio_key !~ '\.\.'),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  transcription text check (length(transcription) between 1 and 500000),
  summary text check (length(summary) between 1 and 50000),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index vtr_transcriptions_item_subject_idx on public.vtr_transcriptions (item_id, subject_id);
create index vtr_transcriptions_subject_status_idx on public.vtr_transcriptions (subject_id, status, created_at desc);
create index vtr_transcriptions_requested_by_idx on public.vtr_transcriptions (requested_by);

create function public.vtr_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'voice_transcription') then
    raise exception 'vtr_transcriptions requires an item of kind voice_transcription' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger vtr_transcriptions_kind before insert on public.vtr_transcriptions for each row execute function public.vtr_check_kind();


-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.vtr_request(p_subject uuid, p_audio_key text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'vtr.transcribe'), 1) into v_cost;
  v_key := 'vtr:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'vtr.transcribe', 'vtr_transcriptions', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'voice_transcription', left(coalesce(null::text, 'Transcription'), 200), 'vtr');
  insert into public.vtr_transcriptions (item_id, subject_id, requested_by, audio_key, cost, charge_key)
    values (v_id, p_subject, v_user, p_audio_key, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.vtr_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.vtr_transcriptions set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.vtr_complete(p_item uuid, p_transcription text, p_summary text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.vtr_transcriptions set status = 'succeeded', error = null, completed_at = now(), transcription = p_transcription, summary = p_summary
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.vtr_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.vtr_transcriptions%rowtype;
begin
  update public.vtr_transcriptions set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'vtr.transcribe', 'vtr_transcriptions', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.vtr_record(p_subject uuid, p_user uuid, p_external_ref text, p_audio_key text, p_transcription text, p_summary text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('vtr:' || p_external_ref, 0));
  select item_id into v_existing from public.vtr_transcriptions where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'voice_transcription', left(coalesce(null::text, 'Transcription'), 200), 'vtr');
  insert into public.vtr_transcriptions (item_id, subject_id, requested_by, audio_key, prediction_id, status, transcription, summary, cost, completed_at)
    values (v_id, p_subject, p_user, p_audio_key, p_external_ref, 'succeeded', p_transcription, p_summary, 0, now());
  return v_id;
end $$;
revoke execute on function public.vtr_check_kind(), public.vtr_mark_started(uuid, text), public.vtr_complete(uuid, text, text), public.vtr_fail(uuid, text), public.vtr_record(uuid, uuid, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.vtr_request(uuid, text) from public, anon;
grant execute on function public.vtr_request(uuid, text) to authenticated;

alter table public.vtr_transcriptions enable row level security;
create policy vtr_transcriptions_select on public.vtr_transcriptions for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.vtr_transcriptions');
grant select on public.vtr_transcriptions to authenticated;
