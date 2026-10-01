-- item-search: profiles -> candidates -> (accepted) items -> dispatches. The matcher that fills is_candidates and the worker that drains
-- is_dispatches are external and use the service role; this pack is the schema, the access rules and the queue contract.

create table public.is_profiles (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  kind        text not null check (kind ~ '^[a-z][a-z0-9_]{1,29}$'),
  name        text not null check (length(name) between 1 and 100),
  active      boolean not null default true,
  criteria    jsonb not null default '[]'::jsonb check (jsonb_typeof(criteria) = 'array' and jsonb_array_length(criteria) <= 20),
  exclusions  jsonb not null default '{}'::jsonb check (jsonb_typeof(exclusions) = 'object'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, subject_id)
);
create index is_profiles_subject_idx on public.is_profiles (subject_id, active);
create trigger is_profiles_updated_at before update on public.is_profiles for each row execute function public.set_updated_at();

create table public.is_candidates (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null,
  subject_id   uuid not null,
  external_ref text not null check (length(external_ref) between 1 and 300),
  title        text not null check (length(title) between 1 and 200),
  url          text check (url is null or url ~* '^https?://'),
  source       text check (source is null or length(source) <= 100),
  reason       jsonb not null default '{}'::jsonb check (jsonb_typeof(reason) = 'object'),
  status       text not null default 'new' check (status in ('new','accepted','dismissed')),
  item_id      uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (profile_id, external_ref),
  foreign key (profile_id, subject_id) references public.is_profiles (id, subject_id) on delete cascade,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete set null (item_id)
);
create index is_candidates_profile_idx on public.is_candidates (profile_id, subject_id, status);
create index is_candidates_item_idx on public.is_candidates (item_id, subject_id);
create index is_candidates_subject_idx on public.is_candidates (subject_id);
create trigger is_candidates_updated_at before update on public.is_candidates for each row execute function public.set_updated_at();

create table public.is_dispatches (
  id           uuid primary key default gen_random_uuid(),
  item_id      uuid not null,
  subject_id   uuid not null references public.subjects(id) on delete cascade,
  status       text not null default 'pending_review' check (status in ('pending_review','approved','claimed','done','failed','cancelled')),
  payload      jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  overrides    jsonb not null default '{}'::jsonb check (jsonb_typeof(overrides) = 'object' and pg_column_size(overrides) < 20000),
  release_at   timestamptz not null default now(),
  attempts     integer not null default 0,
  error        text check (error is null or length(error) <= 2000),
  reviewed_at  timestamptz,
  claimed_at   timestamptz,
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index is_dispatches_item_idx on public.is_dispatches (item_id, subject_id);
create index is_dispatches_subject_idx on public.is_dispatches (subject_id, status);
create index is_dispatches_queue_idx on public.is_dispatches (release_at) where status in ('approved','claimed');
create trigger is_dispatches_updated_at before update on public.is_dispatches for each row execute function public.set_updated_at();

-- Service-only event outbox: tells the external matcher / worker that something changed (poll with is_claim_outbox).
create table public.is_outbox (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  topic       text not null check (topic ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  ref_id      uuid not null,
  status      text not null default 'pending' check (status in ('pending','sending','sent')),
  attempts    integer not null default 0,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);
create index is_outbox_subject_idx on public.is_outbox (subject_id);
create index is_outbox_pending_idx on public.is_outbox (created_at) where status in ('pending','sending');

create function public.is_emit(p_subject uuid, p_topic text, p_ref uuid) returns void
language sql security definer set search_path = '' as $$
  insert into public.is_outbox (subject_id, topic, ref_id) values (p_subject, p_topic, p_ref)
$$;

-- Plan cap on search profiles per subject. Service-role and migration code (no auth.uid()) is exempt.
create function public.is_enforce_profile_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_tier text; v_limit integer; v_count integer;
begin
  if (select auth.uid()) is null then return new; end if;
  select p.tier into v_tier from public.subjects s join public.profiles p on p.id = s.owner_id where s.id = new.subject_id;
  v_limit := public.get_plan_limit(coalesce(v_tier, 'free'), 'is_max_profiles', 3);
  select count(*) into v_count from public.is_profiles where subject_id = new.subject_id;
  if v_count >= v_limit then raise exception 'is_max_profiles limit reached (%)', v_limit using errcode = '53400'; end if;
  return new;
end $$;
create trigger is_profiles_limit before insert on public.is_profiles for each row execute function public.is_enforce_profile_limit();

create function public.is_profile_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.is_emit(new.subject_id, 'profile.changed', new.id);
  return new;
end $$;
create trigger is_profiles_changed after insert or update of kind, active, criteria, exclusions on public.is_profiles for each row execute function public.is_profile_changed();

create function public.is_dispatch_approved() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    perform public.is_emit(new.subject_id, 'dispatch.approved', new.id);
  end if;
  return new;
end $$;
create trigger is_dispatches_approved after update of status on public.is_dispatches for each row execute function public.is_dispatch_approved();

-- ---------------------------------------------------------------------------
-- User-facing functions. They run as definer, so each one checks the caller, the MFA gate and subject access itself.
-- ---------------------------------------------------------------------------
create function public.is_accept_candidate(p_candidate uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c public.is_candidates; k text; v_item uuid;
begin
  select * into c from public.is_candidates where id = p_candidate for update;
  if not found or (select auth.uid()) is null or not public.has_subject_access(c.subject_id) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if c.status = 'accepted' and c.item_id is not null then return c.item_id; end if;
  select kind into k from public.is_profiles where id = c.profile_id;
  insert into public.it_items (subject_id, kind, title, url, source) values (c.subject_id, k, c.title, c.url, c.source) returning id into v_item;
  update public.is_candidates set status = 'accepted', item_id = v_item where id = c.id;
  perform public.is_emit(c.subject_id, 'candidate.accepted', c.id);
  return v_item;
end $$;

create function public.is_dismiss_candidate(p_candidate uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.is_candidates where id = p_candidate;
  if v_subject is null or (select auth.uid()) is null or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.is_candidates set status = 'dismissed' where id = p_candidate and status = 'new';
end $$;

create function public.is_set_dispatch_overrides(p_id uuid, p_overrides jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.is_dispatches where id = p_id;
  if v_subject is null or (select auth.uid()) is null or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.is_dispatches set overrides = p_overrides where id = p_id and status = 'pending_review';
  if not found then raise exception 'dispatch is not pending review' using errcode = '23514'; end if;
end $$;

create function public.is_approve_dispatch(p_id uuid, p_delay_seconds integer default 0) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.is_dispatches where id = p_id;
  if v_subject is null or (select auth.uid()) is null or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_delay_seconds < 0 or p_delay_seconds > 604800 then raise exception 'delay must be 0..604800 seconds' using errcode = '23514'; end if;
  update public.is_dispatches set status = 'approved', reviewed_at = now(), release_at = now() + make_interval(secs => p_delay_seconds)
   where id = p_id and status = 'pending_review';
  if not found then raise exception 'dispatch is not pending review' using errcode = '23514'; end if;
end $$;

create function public.is_cancel_dispatch(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.is_dispatches where id = p_id;
  if v_subject is null or (select auth.uid()) is null or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.is_dispatches set status = 'cancelled' where id = p_id and status in ('pending_review', 'approved');
  if not found then raise exception 'dispatch can no longer be cancelled' using errcode = '23514'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Worker contract (service role only; these are not granted to API roles). Claims are exactly-once under concurrency;
-- a claim older than 10 minutes is retried, and abandoned after 5 attempts.
-- ---------------------------------------------------------------------------
create function public.is_claim_next_dispatch() returns setof public.is_dispatches
language plpgsql set search_path = '' as $$
begin
  update public.is_dispatches set status = 'failed', error = 'abandoned after 5 attempts', completed_at = now()
   where status = 'claimed' and claimed_at < now() - interval '10 minutes' and attempts >= 5;
  return query
  update public.is_dispatches d set status = 'claimed', claimed_at = now(), attempts = d.attempts + 1
   where d.id = (select x.id from public.is_dispatches x
                  where (x.status = 'approved' and x.release_at <= now())
                     or (x.status = 'claimed' and x.claimed_at < now() - interval '10 minutes' and x.attempts < 5)
                  order by x.release_at for update skip locked limit 1)
  returning d.*;
end $$;

create function public.is_complete_dispatch(p_id uuid, p_ok boolean, p_error text default null) returns void
language plpgsql set search_path = '' as $$
begin
  update public.is_dispatches set status = case when p_ok then 'done' else 'failed' end, completed_at = now(),
         error = case when p_ok then null else left(coalesce(p_error, 'failed'), 2000) end
   where id = p_id and status = 'claimed';
  if not found then raise exception 'dispatch is not claimed' using errcode = '23514'; end if;
end $$;

create function public.is_claim_outbox(p_limit integer default 50) returns setof public.is_outbox
language sql set search_path = '' as $$
  update public.is_outbox set status = 'sending', attempts = attempts + 1
   where id in (select id from public.is_outbox
                 where (status = 'pending' or (status = 'sending' and created_at < now() - interval '10 minutes')) and attempts < 5
                 order by created_at for update skip locked limit greatest(1, least(p_limit, 200)))
  returning *
$$;

alter table public.is_profiles enable row level security;
alter table public.is_candidates enable row level security;
alter table public.is_dispatches enable row level security;
alter table public.is_outbox enable row level security;   -- no policies and no grants: service role only
create policy is_profiles_select on public.is_profiles for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy is_profiles_insert on public.is_profiles for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy is_profiles_update on public.is_profiles for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy is_profiles_delete on public.is_profiles for delete to authenticated using ((select public.is_subject_owner(subject_id)));
create policy is_candidates_select on public.is_candidates for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy is_dispatches_select on public.is_dispatches for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.is_profiles');
select public.apply_mfa_gate('public.is_candidates');
select public.apply_mfa_gate('public.is_dispatches');

grant select, delete on public.is_profiles to authenticated;
grant insert (subject_id, kind, name, active, criteria, exclusions) on public.is_profiles to authenticated;
grant update (name, active, criteria, exclusions) on public.is_profiles to authenticated;
grant select on public.is_candidates to authenticated;
grant select on public.is_dispatches to authenticated;
grant execute on function public.is_accept_candidate(uuid), public.is_dismiss_candidate(uuid), public.is_set_dispatch_overrides(uuid, jsonb),
      public.is_approve_dispatch(uuid, integer), public.is_cancel_dispatch(uuid) to authenticated;
