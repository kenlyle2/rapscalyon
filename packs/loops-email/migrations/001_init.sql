create table public.lp_outbox (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  event       text not null check (event ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  properties  jsonb not null default '{}'::jsonb check (jsonb_typeof(properties) = 'object'),
  status      text not null default 'pending' check (status in ('pending','sending','sent','failed','suppressed')),
  attempts    integer not null default 0,
  last_error  text,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);
create index lp_outbox_profile_idx on public.lp_outbox (profile_id, created_at desc);
create index lp_outbox_pending_idx on public.lp_outbox (created_at) where status = 'pending';

create table public.lp_preferences (
  profile_id    uuid primary key references public.profiles(id) on delete cascade,
  marketing     boolean not null default true,
  product       boolean not null default true,
  unsubscribed_at timestamptz,
  updated_at    timestamptz not null default now()
);
create trigger lp_preferences_updated_at before update on public.lp_preferences for each row execute function public.set_updated_at();

alter table public.lp_outbox enable row level security;
alter table public.lp_preferences enable row level security;

-- users can see what was sent to them; only the server enqueues, claims and marks rows
create policy lp_outbox_select on public.lp_outbox for select to authenticated using (profile_id = (select auth.uid()));
select public.apply_mfa_gate('public.lp_outbox');
grant select on public.lp_outbox to authenticated;

create policy lp_prefs_select on public.lp_preferences for select to authenticated using (profile_id = (select auth.uid()));
create policy lp_prefs_insert on public.lp_preferences for insert to authenticated with check (profile_id = (select auth.uid()));
create policy lp_prefs_update on public.lp_preferences for update to authenticated using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));
select public.apply_mfa_gate('public.lp_preferences');
grant select on public.lp_preferences to authenticated;
grant insert (profile_id, marketing, product) on public.lp_preferences to authenticated;
grant update (marketing, product) on public.lp_preferences to authenticated;

-- Enqueue an event for a profile (service role / other packs' server code). Honors preferences:
-- events named marketing.* are suppressed when marketing is off; everything is suppressed once unsubscribed.
create function public.lp_enqueue(p_profile uuid, p_event text, p_properties jsonb default '{}'::jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare pref public.lp_preferences; st text := 'pending'; pend int; new_id uuid;
begin
  select * into pref from public.lp_preferences where profile_id = p_profile;
  if found and (pref.unsubscribed_at is not null or (p_event like 'marketing.%' and not pref.marketing)) then st := 'suppressed'; end if;
  select count(*) into pend from public.lp_outbox where profile_id = p_profile and status = 'pending';
  if pend >= public.get_plan_limit((select tier from public.profiles where id = p_profile), 'lp_max_pending', 500) then
    raise exception 'outbox full for profile';
  end if;
  insert into public.lp_outbox (profile_id, event, properties, status) values (p_profile, p_event, coalesce(p_properties, '{}'::jsonb), st) returning id into new_id;
  return new_id;
end $$;

-- Sender claims rows exactly once, even with concurrent workers; stale 'sending' rows are retried (max 5 attempts).
create function public.lp_claim_outbox(p_limit integer default 50) returns setof public.lp_outbox
language sql security definer set search_path = '' as $$
  update public.lp_outbox set status = 'sending', attempts = attempts + 1
   where id in (select id from public.lp_outbox
                 where (status = 'pending' or (status = 'sending' and created_at < now() - interval '10 minutes')) and attempts < 5
                 order by created_at for update skip locked limit greatest(1, least(p_limit, 200)))
  returning *
$$;

create function public.lp_stuck_outbox() returns bigint
language sql stable security definer set search_path = '' as $$
  select count(*) from public.lp_outbox where status in ('pending','sending') and created_at < now() - interval '30 minutes'
$$;
