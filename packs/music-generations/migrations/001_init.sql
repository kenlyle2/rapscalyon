-- music-generations: Text-to-music generation jobs (the BuilderKit music_generations table) as a child of item-tracker: prompt, genre, mood, duration and an audio key, charged up front or recorded from an outside generator.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.mgn_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.mgn_valid_keys(text[], integer) from public, anon, authenticated;

create table public.mgn_tracks (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  prompt text not null check (length(prompt) between 1 and 2000),
  genre text not null check (length(genre) between 1 and 60),
  mood text not null check (length(mood) between 1 and 60),
  duration integer not null check (duration between 1 and 600),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  output_keys    text[] not null default '{}' check (mgn_valid_keys(output_keys, 1)),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index mgn_tracks_item_subject_idx on public.mgn_tracks (item_id, subject_id);
create index mgn_tracks_subject_status_idx on public.mgn_tracks (subject_id, status, created_at desc);
create index mgn_tracks_requested_by_idx on public.mgn_tracks (requested_by);

create function public.mgn_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'music_track') then
    raise exception 'mgn_tracks requires an item of kind music_track' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger mgn_tracks_kind before insert on public.mgn_tracks for each row execute function public.mgn_check_kind();


-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.mgn_request(p_subject uuid, p_prompt text, p_genre text, p_mood text, p_duration integer) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'mgn.generate'), 1) into v_cost;
  v_key := 'mgn:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'mgn.generate', 'mgn_tracks', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'music_track', left(coalesce(left(p_genre || ' - ' || p_mood, 200), 'Music track'), 200), 'mgn');
  insert into public.mgn_tracks (item_id, subject_id, requested_by, prompt, genre, mood, duration, cost, charge_key)
    values (v_id, p_subject, v_user, p_prompt, p_genre, p_mood, p_duration, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.mgn_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.mgn_tracks set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.mgn_complete(p_item uuid, p_keys text[]) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.mgn_tracks set status = 'succeeded', error = null, completed_at = now(), output_keys = coalesce(p_keys, '{}')
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.mgn_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.mgn_tracks%rowtype;
begin
  update public.mgn_tracks set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'mgn.generate', 'mgn_tracks', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.mgn_record(p_subject uuid, p_user uuid, p_external_ref text, p_prompt text, p_genre text, p_mood text, p_duration integer, p_keys text[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('mgn:' || p_external_ref, 0));
  select item_id into v_existing from public.mgn_tracks where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'music_track', left(coalesce(left(p_genre || ' - ' || p_mood, 200), 'Music track'), 200), 'mgn');
  insert into public.mgn_tracks (item_id, subject_id, requested_by, prompt, genre, mood, duration, prediction_id, status, output_keys, cost, completed_at)
    values (v_id, p_subject, p_user, p_prompt, p_genre, p_mood, p_duration, p_external_ref, 'succeeded', coalesce(p_keys, '{}'), 0, now());
  return v_id;
end $$;
revoke execute on function public.mgn_check_kind(), public.mgn_mark_started(uuid, text), public.mgn_complete(uuid, text[]), public.mgn_fail(uuid, text), public.mgn_record(uuid, uuid, text, text, text, text, integer, text[]) from public, anon, authenticated;
revoke execute on function public.mgn_request(uuid, text, text, text, integer) from public, anon;
grant execute on function public.mgn_request(uuid, text, text, text, integer) to authenticated;

alter table public.mgn_tracks enable row level security;
create policy mgn_tracks_select on public.mgn_tracks for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.mgn_tracks');
grant select on public.mgn_tracks to authenticated;
