-- RapScalYon core foundation 0.1.0  (AGPL-3.0-or-later)
-- Generic app skeleton: accounts, credits/limits, billing events, subjects (workspaces), audit/health.
-- Security stance: default-deny. Nothing in `public` is reachable by anon; authenticated gets explicit,
-- minimal grants only. Every definer function pins search_path = ''.

-- ---------------------------------------------------------------------------
-- 0. Default-deny for objects created from here on (packs inherit this)
-- ---------------------------------------------------------------------------
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
-- PUBLIC's built-in EXECUTE can only be removed by the global (not schema-scoped) form:
alter default privileges revoke execute on functions from public;
-- service_role is the trusted backend: everything a pack creates is usable by it without per-pack grants.
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

-- ---------------------------------------------------------------------------
-- 1. Shared trigger helpers
-- ---------------------------------------------------------------------------
create function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 2. profiles (id = auth uid). No secrets live here.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                       uuid primary key references auth.users(id) on delete cascade,
  email                    text not null unique,
  display_name             text,
  timezone                 text not null default 'UTC',
  locale                   text not null default 'en',
  is_admin                 boolean not null default false,
  tier                     text not null default 'free',
  subscription_status      text,
  trial_ends_at            timestamptz,
  usage_daily              integer not null default 0 check (usage_daily >= 0),
  usage_monthly            integer not null default 0 check (usage_monthly >= 0),
  usage_daily_date         date    not null default current_date,
  usage_month              date    not null default date_trunc('month', current_date)::date,
  billing_provider         text,
  billing_customer_ref     text,
  billing_subscription_ref text,
  billing_status           text,
  billing_plan_key         text,
  billing_updated_at       timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index profiles_billing_customer_idx     on public.profiles (billing_customer_ref)     where billing_customer_ref is not null;
create index profiles_billing_subscription_idx on public.profiles (billing_subscription_ref) where billing_subscription_ref is not null;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email) values (new.id, coalesce(new.email, new.id::text || '@anonymous.invalid'))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = (select auth.uid())), false)
$$;

-- ---------------------------------------------------------------------------
-- 3. Credentials: provider tokens/API keys. Service-role only, never in profiles.
-- ---------------------------------------------------------------------------
create table public.user_credentials (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  provider   text not null,
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, provider)
);
create trigger user_credentials_updated_at before update on public.user_credentials for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. admin_settings + plan limits
-- ---------------------------------------------------------------------------
create table public.admin_settings (
  setting_key   text primary key,
  setting_value jsonb not null,
  updated_at    timestamptz not null default now()
);
create trigger admin_settings_updated_at before update on public.admin_settings for each row execute function public.set_updated_at();

-- plan_limits shape: {"<tier>": {"daily": int, "monthly": int, "<pack_limit_key>": int, ...}}
create function public.get_plan_limit(p_tier text, p_key text, p_default integer) returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select (s.setting_value -> p_tier ->> p_key)::integer from public.admin_settings s where s.setting_key = 'plan_limits'),
    p_default)
$$;

create function public.get_my_limits() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select s.setting_value -> p.tier from public.admin_settings s, public.profiles p
                   where s.setting_key = 'plan_limits' and p.id = (select auth.uid())), '{}'::jsonb)
$$;

-- ---------------------------------------------------------------------------
-- 5. Billing events (provider-agnostic webhook ledger)
-- ---------------------------------------------------------------------------
create table public.billing_events (
  id                uuid primary key default gen_random_uuid(),
  source            text not null,
  event_type        text not null,
  external_id       text not null,
  raw_payload       jsonb not null,
  processing_status text not null default 'pending' check (processing_status in ('pending','success','partial','failed')),
  processing_notes  jsonb,
  retry_count       integer not null default 0,
  profile_id        uuid references public.profiles(id) on delete set null,
  alerted           boolean not null default false,
  alerted_at        timestamptz,
  created_at        timestamptz not null default now(),
  processed_at      timestamptz,
  unique (source, external_id)
);
create index billing_events_profile_idx on public.billing_events (profile_id);
create index billing_events_unprocessed_idx on public.billing_events (created_at) where processing_status <> 'success';

-- ---------------------------------------------------------------------------
-- 6. Pricing + credit ledger
-- ---------------------------------------------------------------------------
create table public.operation_pricing (
  operation   text primary key,
  credit_cost integer not null check (credit_cost >= 0),
  label       text not null,
  pack        text,
  updated_at  timestamptz not null default now()
);
create trigger operation_pricing_updated_at before update on public.operation_pricing for each row execute function public.set_updated_at();

create table public.credit_usage_log (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  amount          integer not null,
  operation       text,
  idempotency_key text,
  ref_type        text,
  ref_id          uuid,
  daily_after     integer not null,
  monthly_after   integer not null,
  created_at      timestamptz not null default now()
);
create index credit_usage_log_user_idx on public.credit_usage_log (user_id, created_at desc);
create unique index credit_usage_log_idem_idx on public.credit_usage_log (user_id, idempotency_key) where idempotency_key is not null;

-- p_cost > 0 charges. p_cost < 0 refunds a prior charge: p_idempotency_key must be '<original key>:refund'
-- and the original charge must exist for exactly -p_cost. A charge can be refunded once.
create function public.charge_credits(p_user_id uuid, p_cost integer, p_idempotency_key text, p_operation text default null,
                                      p_ref_type text default null, p_ref_id uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_existing public.credit_usage_log%rowtype;
  v_orig_key text;
  v_orig public.credit_usage_log%rowtype;
  v_daily_limit integer;
  v_monthly_limit integer;
  v_today date := current_date;
  v_month date := date_trunc('month', current_date)::date;
  v_daily integer;
  v_monthly integer;
begin
  if p_idempotency_key is null then
    return jsonb_build_object('success', false, 'error', 'IDEMPOTENCY_KEY_REQUIRED');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_idempotency_key, 0));

  select * into v_existing from public.credit_usage_log where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('success', true, 'duplicate', true, 'daily', v_existing.daily_after, 'monthly', v_existing.monthly_after);
  end if;

  select * into v_profile from public.profiles where id = p_user_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'NO_PROFILE');
  end if;

  v_daily   := case when v_profile.usage_daily_date = v_today then v_profile.usage_daily else 0 end;
  v_monthly := case when v_profile.usage_month = v_month then v_profile.usage_monthly else 0 end;

  if p_cost < 0 then
    if right(p_idempotency_key, 7) <> ':refund' then
      return jsonb_build_object('success', false, 'error', 'REFUND_KEY_INVALID');
    end if;
    v_orig_key := left(p_idempotency_key, length(p_idempotency_key) - 7);
    select * into v_orig from public.credit_usage_log where user_id = p_user_id and idempotency_key = v_orig_key and amount > 0;
    if not found or v_orig.amount <> -p_cost then
      return jsonb_build_object('success', false, 'error', 'NO_MATCHING_CHARGE');
    end if;
  else
    v_daily_limit   := public.get_plan_limit(v_profile.tier, 'daily', 10);
    v_monthly_limit := public.get_plan_limit(v_profile.tier, 'monthly', 50);
    if v_daily + p_cost > v_daily_limit then
      return jsonb_build_object('success', false, 'error', 'DAILY_LIMIT_EXCEEDED', 'daily', v_daily, 'limit', v_daily_limit);
    end if;
    if v_monthly + p_cost > v_monthly_limit then
      return jsonb_build_object('success', false, 'error', 'MONTHLY_LIMIT_EXCEEDED', 'monthly', v_monthly, 'limit', v_monthly_limit);
    end if;
  end if;

  v_daily   := greatest(0, v_daily + p_cost);
  v_monthly := greatest(0, v_monthly + p_cost);

  update public.profiles set usage_daily = v_daily, usage_monthly = v_monthly, usage_daily_date = v_today, usage_month = v_month
   where id = p_user_id;
  insert into public.credit_usage_log (user_id, amount, operation, idempotency_key, ref_type, ref_id, daily_after, monthly_after)
  values (p_user_id, p_cost, p_operation, p_idempotency_key, p_ref_type, p_ref_id, v_daily, v_monthly);

  return jsonb_build_object('success', true, 'daily', v_daily, 'monthly', v_monthly);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Rate limiting (fixed window, atomic)
-- ---------------------------------------------------------------------------
create table public.rate_limits (
  key          text primary key,
  count        integer not null default 1,
  window_start timestamptz not null default now()
);

create function public.check_rate_limit(p_key text, p_max integer, p_window_seconds integer) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  insert into public.rate_limits as r (key, count, window_start) values (p_key, 1, now())
  on conflict (key) do update
    set count        = case when r.window_start + make_interval(secs => p_window_seconds) <= now() then 1 else r.count + 1 end,
        window_start = case when r.window_start + make_interval(secs => p_window_seconds) <= now() then now() else r.window_start end
  returning count into v_count;
  return v_count <= p_max;
end $$;

-- ---------------------------------------------------------------------------
-- 8. Subjects: the generic "thing the user's data hangs off" (persona, business location, ...)
-- ---------------------------------------------------------------------------
create table public.subjects (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('individual','business')),
  name       text not null check (length(name) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index subjects_owner_idx on public.subjects (owner_id);
create trigger subjects_updated_at before update on public.subjects for each row execute function public.set_updated_at();

create table public.subject_members (
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  role        text not null default 'member' check (role in ('admin','member','viewer')),
  accepted_at timestamptz,
  created_at  timestamptz not null default now(),
  primary key (subject_id, user_id)
);
create index subject_members_user_idx on public.subject_members (user_id);

-- Owner, or an accepted member. Packs use this in every policy on subject-scoped tables.
create function public.has_subject_access(p_subject_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.subjects s where s.id = p_subject_id and s.owner_id = (select auth.uid()))
      or exists (select 1 from public.subject_members m
                  where m.subject_id = p_subject_id and m.user_id = (select auth.uid()) and m.accepted_at is not null)
$$;

create function public.is_subject_owner(p_subject_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.subjects s where s.id = p_subject_id and s.owner_id = (select auth.uid()))
$$;

-- ---------------------------------------------------------------------------
-- 9. Events + health findings
-- ---------------------------------------------------------------------------
create table public.app_events (
  id          uuid primary key default gen_random_uuid(),
  level       text not null check (level in ('error','warning','info')),
  source      text not null,
  message     text not null,
  details     jsonb,
  user_id     uuid references public.profiles(id) on delete set null,
  context     jsonb,
  created_at  timestamptz not null default now()
);
create index app_events_created_idx on public.app_events (created_at desc);
create index app_events_user_idx on public.app_events (user_id) where user_id is not null;
create index app_events_level_idx on public.app_events (level, created_at desc);

create table public.account_health_findings (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  subject_id    uuid references public.subjects(id) on delete cascade,
  check_id      text not null,
  severity      text not null check (severity in ('low','medium','high','critical')),
  message       text not null,
  details       jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  resolved_at   timestamptz,
  unique nulls not distinct (user_id, subject_id, check_id)
);
create index account_health_findings_subject_idx on public.account_health_findings (subject_id) where subject_id is not null;
create index account_health_findings_open_idx on public.account_health_findings (severity) where resolved_at is null;

-- ---------------------------------------------------------------------------
-- 10. Pack registry
-- ---------------------------------------------------------------------------
create table public.pack_migrations (
  pack       text not null,
  version    text not null,
  filename   text not null,
  checksum   text,
  applied_at timestamptz not null default now(),
  primary key (pack, filename)
);

-- ---------------------------------------------------------------------------
-- 11. MFA gate + RLS safety net
-- ---------------------------------------------------------------------------
create function public.session_satisfies_mfa() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select auth.jwt() ->> 'aal'), 'aal1') = 'aal2'
      or not exists (select 1 from auth.mfa_factors f where f.user_id = (select auth.uid()) and f.status = 'verified')
$$;

-- Adds the restrictive "enrolled users must be at aal2" policy to a table. Run from migrations, not callable via API.
create function public.apply_mfa_gate(p_table regclass) returns void
language plpgsql set search_path = '' as $$
begin
  execute format('drop policy if exists require_mfa_when_enrolled on %s', p_table);
  execute format('create policy require_mfa_when_enrolled on %s as restrictive for all to authenticated using ((select public.session_satisfies_mfa())) with check ((select public.session_satisfies_mfa()))', p_table);
end $$;

create function public.ensure_rls() returns event_trigger
language plpgsql security definer set search_path = '' as $$
declare cmd record;
begin
  for cmd in select * from pg_event_trigger_ddl_commands() where command_tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO') and schema_name = 'public' loop
    execute format('alter table %s enable row level security', cmd.object_identity);
  end loop;
end $$;
create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO') execute function public.ensure_rls();

-- ---------------------------------------------------------------------------
-- 12. RLS
-- ---------------------------------------------------------------------------
alter table public.profiles                enable row level security;
alter table public.user_credentials        enable row level security;
alter table public.admin_settings          enable row level security;
alter table public.billing_events          enable row level security;
alter table public.operation_pricing       enable row level security;
alter table public.credit_usage_log        enable row level security;
alter table public.rate_limits             enable row level security;
alter table public.subjects                enable row level security;
alter table public.subject_members         enable row level security;
alter table public.app_events              enable row level security;
alter table public.account_health_findings enable row level security;
alter table public.pack_migrations         enable row level security;

create policy profiles_select on public.profiles for select to authenticated using (id = (select auth.uid()) or (select public.is_admin()));
create policy profiles_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy admin_settings_admin on public.admin_settings for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy billing_events_admin_read on public.billing_events for select to authenticated using ((select public.is_admin()));
create policy operation_pricing_read on public.operation_pricing for select to authenticated using (true);
create policy operation_pricing_admin_write on public.operation_pricing for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy credit_usage_log_owner_read on public.credit_usage_log for select to authenticated using (user_id = (select auth.uid()));
create policy app_events_admin_read on public.app_events for select to authenticated using ((select public.is_admin()));
create policy findings_read on public.account_health_findings for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy pack_migrations_admin_read on public.pack_migrations for select to authenticated using ((select public.is_admin()));

-- owner_id checked directly so INSERT ... RETURNING works (a STABLE function cannot see the row being inserted)
create policy subjects_select on public.subjects for select to authenticated using (owner_id = (select auth.uid()) or (select public.has_subject_access(id)));
create policy subjects_insert on public.subjects for insert to authenticated with check (owner_id = (select auth.uid()));
create policy subjects_update on public.subjects for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy subjects_delete on public.subjects for delete to authenticated using (owner_id = (select auth.uid()));
create policy subject_members_select on public.subject_members for select to authenticated using (user_id = (select auth.uid()) or (select public.is_subject_owner(subject_id)));

select public.apply_mfa_gate(t) from unnest(array[
  'public.profiles','public.admin_settings','public.billing_events','public.operation_pricing','public.credit_usage_log',
  'public.subjects','public.subject_members','public.app_events','public.account_health_findings','public.pack_migrations'
]::regclass[]) t;

-- ---------------------------------------------------------------------------
-- 13. Grants (explicit minimums; everything else is service_role only)
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

grant select on public.profiles, public.billing_events, public.operation_pricing, public.credit_usage_log,
                public.app_events, public.account_health_findings, public.pack_migrations,
                public.subjects, public.subject_members to authenticated;
grant update (display_name, timezone, locale) on public.profiles to authenticated;
grant select, insert, update, delete on public.admin_settings to authenticated;
grant insert, update, delete on public.operation_pricing to authenticated;
grant insert (kind, name, owner_id), update (name), delete on public.subjects to authenticated;

-- Functions the browser session legitimately calls (policies evaluate them as the caller)
grant execute on function public.is_admin(), public.has_subject_access(uuid), public.is_subject_owner(uuid),
                          public.session_satisfies_mfa(), public.get_my_limits() to authenticated;
-- service_role-only: charge_credits, check_rate_limit, get_plan_limit, apply_mfa_gate, handle_new_user, ensure_rls, set_updated_at
grant execute on all functions in schema public to service_role;
grant all on all tables in schema public to service_role;
