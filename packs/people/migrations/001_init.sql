create table public.ppl_people (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  created_by  uuid references public.profiles(id) on delete set null,
  name        text not null check (length(btrim(name)) between 1 and 200),
  email       text check (email = lower(btrim(email)) and position('@' in email) > 1 and length(email) <= 320),
  phone       text check (length(phone) between 3 and 40),
  kind        text not null default 'contact' check (kind ~ '^[a-z][a-z0-9_]{1,39}$'),
  status      text not null default 'active' check (status in ('active','inactive','archived')),
  assigned_to uuid references public.profiles(id) on delete set null,
  user_id     uuid references public.profiles(id) on delete set null,
  notes       text check (length(notes) <= 4000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index ppl_people_subject_idx on public.ppl_people (subject_id, status, kind);
create index ppl_people_created_by_idx on public.ppl_people (created_by);
create index ppl_people_assigned_to_idx on public.ppl_people (assigned_to);
create unique index ppl_people_login_idx on public.ppl_people (subject_id, user_id) where user_id is not null;
create index ppl_people_user_idx on public.ppl_people (user_id);
-- lets other packs reference (id, subject_id) so a row cannot point at a person from another subject
create unique index ppl_people_id_subject_idx on public.ppl_people (id, subject_id);
create trigger ppl_people_updated_at before update on public.ppl_people for each row execute function public.set_updated_at();

-- Whoever looks after a person must be the owner or an accepted member of the same subject.
create function public.ppl_check_assignee() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.assigned_to is not null and not (
       exists (select 1 from public.subjects s where s.id = new.subject_id and s.owner_id = new.assigned_to)
    or exists (select 1 from public.subject_members m where m.subject_id = new.subject_id and m.user_id = new.assigned_to and m.accepted_at is not null)) then
    raise exception 'assigned_to must belong to the same subject' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function public.ppl_check_assignee() from public, anon, authenticated;
create trigger ppl_people_assignee before insert or update of assigned_to on public.ppl_people for each row execute function public.ppl_check_assignee();

alter table public.ppl_people enable row level security;
-- staff of the subject see everyone; a person with a login sees only their own row
create policy ppl_people_select on public.ppl_people for select to authenticated
  using ((select public.has_subject_access(subject_id)) or user_id = (select auth.uid()));
create policy ppl_people_insert on public.ppl_people for insert to authenticated
  with check ((select public.has_subject_access(subject_id)) and created_by = (select auth.uid()));
create policy ppl_people_update on public.ppl_people for update to authenticated
  using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy ppl_people_delete on public.ppl_people for delete to authenticated
  using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.ppl_people');

-- user_id is never written directly: it is set by ppl_claim and cleared by ppl_unlink_login
grant select on public.ppl_people to authenticated;
grant insert (subject_id, created_by, name, email, phone, kind, status, assigned_to, notes) on public.ppl_people to authenticated;
grant update (name, email, phone, kind, status, assigned_to, notes) on public.ppl_people to authenticated;
grant delete on public.ppl_people to authenticated;

-- One-time invitations to attach a login. The token is a bearer credential, so no user can read this table.
create table public.ppl_claims (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references public.ppl_people(id) on delete cascade,
  token      uuid not null unique default gen_random_uuid(),
  expires_at timestamptz not null default now() + interval '7 days',
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);
create index ppl_claims_person_idx on public.ppl_claims (person_id);
create unique index ppl_claims_open_idx on public.ppl_claims (person_id) where claimed_at is null;
alter table public.ppl_claims enable row level security;
select public.apply_mfa_gate('public.ppl_claims');

-- Where this person also exists in an outside system (a CRM, a mailing list). No rows when the business uses none.
create table public.ppl_external_refs (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  person_id   uuid not null,
  system      text not null check (system ~ '^[a-z][a-z0-9_]{1,39}$'),
  external_id text not null check (length(external_id) between 1 and 200),
  synced_at   timestamptz,
  created_at  timestamptz not null default now(),
  foreign key (person_id, subject_id) references public.ppl_people (id, subject_id) on delete cascade,
  unique (person_id, system),
  unique (subject_id, system, external_id)
);
create index ppl_external_refs_person_idx on public.ppl_external_refs (person_id, subject_id);
alter table public.ppl_external_refs enable row level security;
create policy ppl_external_refs_select on public.ppl_external_refs for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy ppl_external_refs_insert on public.ppl_external_refs for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy ppl_external_refs_update on public.ppl_external_refs for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy ppl_external_refs_delete on public.ppl_external_refs for delete to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.ppl_external_refs');
grant select, delete on public.ppl_external_refs to authenticated;
grant insert (subject_id, person_id, system, external_id, synced_at) on public.ppl_external_refs to authenticated;
grant update (external_id, synced_at) on public.ppl_external_refs to authenticated;

-- Staff: make a one-time token the person redeems after signing in. Returns the token for the app to put in a link.
create function public.ppl_invite_login(p_person uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare p public.ppl_people%rowtype; v_token uuid;
begin
  select * into p from public.ppl_people where id = p_person;
  if not found or not public.has_subject_access(p.subject_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p.user_id is not null then raise exception 'this person already has a login' using errcode = '23505'; end if;
  if p.email is null then raise exception 'add an email address first' using errcode = '23514'; end if;
  insert into public.ppl_claims (person_id) values (p_person)
  on conflict (person_id) where claimed_at is null
  do update set token = gen_random_uuid(), expires_at = now() + interval '7 days'
  returning token into v_token;
  return v_token;
end $$;

-- The invited person, signed in, redeems the token; their account email must match the person's email.
create function public.ppl_claim(p_token uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_email text; c public.ppl_claims%rowtype; p public.ppl_people%rowtype;
begin
  if v_uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select email into v_email from public.profiles where id = v_uid;
  select * into c from public.ppl_claims where token = p_token and claimed_at is null and expires_at > now() for update;
  if not found then raise exception 'invalid or expired invite' using errcode = '42501'; end if;
  select * into p from public.ppl_people where id = c.person_id for update;
  if p.user_id is not null or p.email is null or lower(v_email) <> p.email then
    raise exception 'invalid or expired invite' using errcode = '42501';
  end if;
  update public.ppl_people set user_id = v_uid where id = p.id;
  update public.ppl_claims set claimed_at = now() where id = c.id;
  return p.id;
end $$;

-- Staff: detach a login (the person row and its history stay).
create function public.ppl_unlink_login(p_person uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.ppl_people where id = p_person;
  if v_subject is null or not public.has_subject_access(v_subject) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.ppl_people set user_id = null where id = p_person;
end $$;

-- For other packs' policies: is this person row the signed-in user's own?
create function public.ppl_is_self(p_person uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ppl_people p where p.id = p_person and p.user_id = (select auth.uid()))
$$;

revoke all on function public.ppl_invite_login(uuid), public.ppl_claim(uuid), public.ppl_unlink_login(uuid), public.ppl_is_self(uuid) from public, anon;
grant execute on function public.ppl_invite_login(uuid), public.ppl_claim(uuid), public.ppl_unlink_login(uuid), public.ppl_is_self(uuid) to authenticated;
