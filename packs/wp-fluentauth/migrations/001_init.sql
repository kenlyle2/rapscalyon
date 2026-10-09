-- wp-fluentauth: one row per profile that has opened the app from WordPress. Written by the confirm route (service role).
create table public.wf_handoffs (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  handoffs   bigint not null default 1 check (handoffs >= 1),
  first_at   timestamptz not null default now(),
  last_at    timestamptz not null default now()
);

alter table public.wf_handoffs enable row level security;
-- operators only; users have no reason to read it
create policy wf_handoffs_admin_select on public.wf_handoffs for select to authenticated using ((select public.is_admin()));
select public.apply_mfa_gate('public.wf_handoffs');
grant select on public.wf_handoffs to authenticated;

create function public.wf_record_handoff(p_profile uuid) returns bigint
language sql security definer set search_path = '' as $$
  insert into public.wf_handoffs (profile_id) values (p_profile)
  on conflict (profile_id) do update set handoffs = public.wf_handoffs.handoffs + 1, last_at = now()
  returning handoffs
$$;
