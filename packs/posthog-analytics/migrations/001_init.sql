create table public.ph_consent (
  profile_id     uuid primary key references public.profiles(id) on delete cascade,
  analytics      boolean not null default true,
  session_replay boolean not null default false,
  updated_at     timestamptz not null default now()
);
create trigger ph_consent_updated_at before update on public.ph_consent for each row execute function public.set_updated_at();

alter table public.ph_consent enable row level security;
create policy ph_consent_select on public.ph_consent for select to authenticated using (profile_id = (select auth.uid()));
create policy ph_consent_insert on public.ph_consent for insert to authenticated with check (profile_id = (select auth.uid()));
create policy ph_consent_update on public.ph_consent for update to authenticated using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));
select public.apply_mfa_gate('public.ph_consent');
grant select on public.ph_consent to authenticated;
grant insert (profile_id, analytics, session_replay) on public.ph_consent to authenticated;
grant update (analytics, session_replay) on public.ph_consent to authenticated;

-- Server-side gate: may events (kind 'analytics') or recordings (kind 'replay') be sent for this profile?
-- No consent row means analytics allowed, replay not.
create function public.ph_may_track(p_profile uuid, p_kind text default 'analytics') returns boolean
language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'replay' then coalesce((select c.session_replay and c.analytics from public.ph_consent c where c.profile_id = p_profile), false)
    else coalesce((select c.analytics from public.ph_consent c where c.profile_id = p_profile), true) end
$$;
