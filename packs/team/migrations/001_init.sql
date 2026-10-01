create table public.team_invites (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  email       text not null check (email = lower(email) and position('@' in email) > 1),
  role        text not null default 'member' check (role in ('admin','member','viewer')),
  token       uuid not null unique default gen_random_uuid(),
  invited_by  uuid not null references public.profiles(id) on delete cascade,
  expires_at  timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  created_at  timestamptz not null default now()
);
create index team_invites_subject_idx on public.team_invites (subject_id);
create index team_invites_invited_by_idx on public.team_invites (invited_by);
create unique index team_invites_open_idx on public.team_invites (subject_id, email) where accepted_at is null;

alter table public.team_invites enable row level security;
-- only the subject owner sees invites (the token is a bearer credential); all writes go through the functions below
create policy team_invites_owner_select on public.team_invites for select to authenticated using ((select public.is_subject_owner(subject_id)));
select public.apply_mfa_gate('public.team_invites');
grant select (id, subject_id, email, role, expires_at, accepted_at, created_at) on public.team_invites to authenticated;

-- Owner invites an email. Returns the token for the app to put in an email link.
create function public.team_invite(p_subject_id uuid, p_email text, p_role text default 'member') returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_tier text; v_limit integer; v_count integer; v_token uuid;
begin
  if v_uid is null or not public.is_subject_owner(p_subject_id) then
    raise exception 'not the owner of this subject' using errcode = '42501';
  end if;
  select tier into v_tier from public.profiles where id = v_uid;
  v_limit := public.get_plan_limit(coalesce(v_tier, 'free'), 'team_max_members', 3);
  select (select count(*) from public.subject_members where subject_id = p_subject_id)
       + (select count(*) from public.team_invites where subject_id = p_subject_id and accepted_at is null and expires_at > now())
    into v_count;
  if v_count >= v_limit then
    raise exception 'team_max_members limit reached (%)', v_limit using errcode = '53400';
  end if;
  insert into public.team_invites (subject_id, email, role, invited_by)
  values (p_subject_id, lower(trim(p_email)), p_role, v_uid)
  on conflict (subject_id, email) where accepted_at is null
  do update set role = excluded.role, token = gen_random_uuid(), expires_at = now() + interval '7 days'
  returning token into v_token;
  return v_token;
end $$;

-- The invited user redeems the token; their profile email must match the invite.
create function public.team_accept(p_token uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_email text; v_inv public.team_invites%rowtype;
begin
  if v_uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select email into v_email from public.profiles where id = v_uid;
  select * into v_inv from public.team_invites where token = p_token and accepted_at is null and expires_at > now() for update;
  if not found or lower(v_email) <> v_inv.email then
    raise exception 'invalid or expired invite' using errcode = '42501';
  end if;
  insert into public.subject_members (subject_id, user_id, role, accepted_at)
  values (v_inv.subject_id, v_uid, v_inv.role, now())
  on conflict (subject_id, user_id) do update set role = excluded.role, accepted_at = coalesce(public.subject_members.accepted_at, now());
  update public.team_invites set accepted_at = now() where id = v_inv.id;
  return v_inv.subject_id;
end $$;

-- Owner removes a member, or a member leaves.
create function public.team_remove_member(p_subject_id uuid, p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not (public.is_subject_owner(p_subject_id) or p_user_id = v_uid) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from public.subject_members where subject_id = p_subject_id and user_id = p_user_id;
end $$;

grant execute on function public.team_invite(uuid, text, text), public.team_accept(uuid), public.team_remove_member(uuid, uuid) to authenticated;
