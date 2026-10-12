create table public.cal_events (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  person_id  uuid,
  title      text not null check (length(btrim(title)) between 1 and 200),
  notes      text check (length(notes) <= 4000),
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  all_day    boolean not null default false,
  kind       text not null default 'event' check (kind ~ '^[a-z][a-z0-9_]{1,39}$'),
  status     text not null default 'scheduled' check (status in ('scheduled','done','cancelled')),
  -- set only by the feed below: which feature owns this event, and its id there
  source     text check (source ~ '^[a-z][a-z0-9_]{1,39}$'),
  source_ref text check (length(source_ref) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at >= starts_at),
  check ((source is null) = (source_ref is null)),
  -- the person must belong to the same subject; erasing the person keeps the event
  foreign key (person_id, subject_id) references public.ppl_people (id, subject_id) on delete set null (person_id)
);
create index cal_events_window_idx on public.cal_events (subject_id, starts_at);
create index cal_events_created_by_idx on public.cal_events (created_by);
create index cal_events_person_idx on public.cal_events (person_id, subject_id);
create unique index cal_events_source_idx on public.cal_events (subject_id, source, source_ref) where source is not null;
create trigger cal_events_updated_at before update on public.cal_events for each row execute function public.set_updated_at();

alter table public.cal_events enable row level security;
create policy cal_events_select on public.cal_events for select to authenticated using ((select public.has_subject_access(subject_id)));
-- users own only the events they typed in; events from the feed (source set) are read-only to them
create policy cal_events_insert on public.cal_events for insert to authenticated
  with check ((select public.has_subject_access(subject_id)) and created_by = (select auth.uid()) and source is null);
create policy cal_events_update on public.cal_events for update to authenticated
  using ((select public.has_subject_access(subject_id)) and source is null)
  with check ((select public.has_subject_access(subject_id)) and source is null);
create policy cal_events_delete on public.cal_events for delete to authenticated
  using ((select public.has_subject_access(subject_id)) and source is null);
select public.apply_mfa_gate('public.cal_events');

grant select, delete on public.cal_events to authenticated;
grant insert (subject_id, created_by, person_id, title, notes, starts_at, ends_at, all_day, kind, status) on public.cal_events to authenticated;
grant update (person_id, title, notes, starts_at, ends_at, all_day, kind, status) on public.cal_events to authenticated;

-- Feed, service role only: another feature or webhook adds or updates its event here. Idempotent on (subject, source, source_ref).
create function public.cal_upsert_event(p_subject uuid, p_source text, p_ref text, p_kind text, p_title text, p_starts timestamptz, p_ends timestamptz, p_all_day boolean default false, p_person uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  insert into public.cal_events (subject_id, source, source_ref, kind, title, starts_at, ends_at, all_day, person_id)
  values (p_subject, p_source, p_ref, p_kind, p_title, p_starts, p_ends, p_all_day, p_person)
  on conflict (subject_id, source, source_ref) where source is not null
  do update set kind = excluded.kind, title = excluded.title, starts_at = excluded.starts_at, ends_at = excluded.ends_at, all_day = excluded.all_day, person_id = excluded.person_id
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.cal_upsert_event(uuid, text, text, text, text, timestamptz, timestamptz, boolean, uuid) from public, anon, authenticated;

-- Feed, service role only: the owning feature withdraws an event (or all of its events for a subject when p_ref is null).
create function public.cal_remove_source(p_subject uuid, p_source text, p_ref text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  delete from public.cal_events where subject_id = p_subject and source = p_source and (p_ref is null or source_ref = p_ref);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.cal_remove_source(uuid, text, text) from public, anon, authenticated;
