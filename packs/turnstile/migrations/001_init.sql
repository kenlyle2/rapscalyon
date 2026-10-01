create table public.ts_failures (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid references public.profiles(id) on delete set null,
  action      text not null check (action ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  ip_hash     text not null check (length(ip_hash) between 16 and 128),
  reason      text not null check (length(reason) <= 200),
  created_at  timestamptz not null default now()
);
create index ts_failures_profile_idx on public.ts_failures (profile_id) where profile_id is not null;
create index ts_failures_ip_idx on public.ts_failures (ip_hash, created_at desc);
create index ts_failures_created_idx on public.ts_failures (created_at);

alter table public.ts_failures enable row level security;
-- operators only; the log is written by server code (service role)
create policy ts_failures_admin_select on public.ts_failures for select to authenticated using ((select public.is_admin()));
select public.apply_mfa_gate('public.ts_failures');
grant select on public.ts_failures to authenticated;

-- The app hashes the client IP (HMAC with a server secret) before calling; raw IPs are never stored.
create function public.ts_record_failure(p_action text, p_ip_hash text, p_reason text, p_profile uuid default null) returns void
language sql security definer set search_path = '' as $$
  insert into public.ts_failures (profile_id, action, ip_hash, reason) values (p_profile, p_action, p_ip_hash, left(p_reason, 200))
$$;

-- Failures from one IP hash in a window; the app uses this to escalate (block, longer challenge).
create function public.ts_recent_failures(p_ip_hash text, p_minutes integer default 15) returns bigint
language sql stable security definer set search_path = '' as $$
  select count(*) from public.ts_failures where ip_hash = p_ip_hash and created_at > now() - make_interval(mins => greatest(1, least(p_minutes, 1440)))
$$;

create function public.ts_purge_old(p_days integer default 30) returns bigint
language plpgsql security definer set search_path = '' as $$
declare n bigint;
begin
  delete from public.ts_failures where created_at < now() - make_interval(days => greatest(1, p_days));
  get diagnostics n = row_count; return n;
end $$;
