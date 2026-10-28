-- core billing: provider-agnostic subscription sync (moved from the billing-webhook pack, 2026-10-01).
-- Subscription events arrive by POST /api/billing-webhook from a store plugin or any sender that can POST.
-- Idempotent: safe to re-apply (databases that had the old pack keep their data).
-- Maps a provider's plan/product key to an app tier. Admin-managed.
create table if not exists public.bw_plan_map (
  source      text not null check (source ~ '^[a-z][a-z0-9_-]{1,31}$'),
  plan_key    text not null check (length(plan_key) between 1 and 100),
  tier        text not null check (tier ~ '^[a-z][a-z0-9_-]{1,31}$'),
  -- 'exact': plan_key equals the provider's key. 'contains': case-insensitive substring of the product name/SKU
  -- (longest wins, so "PRO PLUS" beats "PRO"), which is how tiers are resolved from WooCommerce product names.
  match_mode  text not null default 'exact' check (match_mode in ('exact','contains')),
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (source, plan_key)
);
create index if not exists bw_plan_map_updated_by_idx on public.bw_plan_map (updated_by) where updated_by is not null;
drop trigger if exists bw_plan_map_updated_at on public.bw_plan_map;
create trigger bw_plan_map_updated_at before update on public.bw_plan_map for each row execute function public.set_updated_at();

alter table public.bw_plan_map enable row level security;
drop policy if exists bw_plan_map_select on public.bw_plan_map;
create policy bw_plan_map_select on public.bw_plan_map for select to authenticated using ((select public.is_admin()));
drop policy if exists bw_plan_map_insert on public.bw_plan_map;
create policy bw_plan_map_insert on public.bw_plan_map for insert to authenticated with check ((select public.is_admin()) and updated_by = (select auth.uid()));
drop policy if exists bw_plan_map_update on public.bw_plan_map;
create policy bw_plan_map_update on public.bw_plan_map for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()) and updated_by = (select auth.uid()));
drop policy if exists bw_plan_map_delete on public.bw_plan_map;
create policy bw_plan_map_delete on public.bw_plan_map for delete to authenticated using ((select public.is_admin()));
select public.apply_mfa_gate('public.bw_plan_map');
grant select, delete on public.bw_plan_map to authenticated;
grant insert (source, plan_key, tier, match_mode, updated_by) on public.bw_plan_map to authenticated;
grant update (tier, match_mode, updated_by) on public.bw_plan_map to authenticated;

-- Apply one normalized provider event. The app-layer adapter verifies the webhook signature and normalizes:
--   p_kind: activated | renewed | payment_failed | canceled | expired | refunded
-- Which kinds drop the profile to 'free' immediately. Default follows WooCommerce semantics:
-- cancelled, expired, failed, on-hold all lose paid access. Admins can change admin_settings.bw_downgrade_on
-- (a JSON array of kinds) to keep access until expiry, e.g. ["expired","refunded"].
-- Idempotent on (source, external_id). Returns: applied | duplicate | stale | unmatched | unmapped_plan
create or replace function public.bw_apply_event(
  p_source text, p_external_id text, p_kind text, p_payload jsonb,
  p_customer_ref text default null, p_subscription_ref text default null,
  p_plan_key text default null, p_email text default null, p_occurred_at timestamptz default now()
) returns text
language plpgsql security definer set search_path = '' as $$
declare ev uuid; prof public.profiles; new_tier text; new_status text; result text := 'applied'; notes jsonb := '{}'::jsonb; downgrade jsonb;
begin
  if p_kind not in ('activated','renewed','payment_failed','canceled','expired','refunded') then
    raise exception 'unknown billing event kind %', p_kind;
  end if;
  insert into public.billing_events (source, event_type, external_id, raw_payload)
  values (p_source, p_kind, p_external_id, coalesce(p_payload, '{}'::jsonb))
  on conflict (source, external_id) do nothing returning id into ev;
  if ev is null then return 'duplicate'; end if;

  select * into prof from public.profiles
   where (p_subscription_ref is not null and billing_subscription_ref = p_subscription_ref)
      or (p_customer_ref is not null and billing_customer_ref = p_customer_ref)
   order by (billing_subscription_ref = p_subscription_ref) desc nulls last limit 1;
  if not found and p_email is not null then
    select * into prof from public.profiles where lower(email) = lower(p_email);
  end if;
  if not found then
    -- 'replay' keeps what bw_replay_unmatched needs to apply this event once the buyer has an account.
    update public.billing_events set processing_status = 'partial', processed_at = now(),
           processing_notes = jsonb_build_object('reason','no matching profile','replay', jsonb_build_object(
             'email', p_email, 'customer_ref', p_customer_ref, 'subscription_ref', p_subscription_ref, 'plan_key', p_plan_key, 'occurred_at', p_occurred_at))
     where id = ev;
    return 'unmatched';
  end if;

  if prof.billing_updated_at is not null and prof.billing_updated_at > p_occurred_at then
    update public.billing_events set profile_id = prof.id, processing_status = 'success', processing_notes = jsonb_build_object('reason','stale event ignored'), processed_at = now() where id = ev;
    return 'stale';
  end if;

  new_status := case p_kind when 'activated' then 'active' when 'renewed' then 'active' when 'payment_failed' then 'past_due'
                            when 'canceled' then 'canceled' else 'expired' end;
  if p_kind in ('activated','renewed') then
    select tier into new_tier from public.bw_plan_map m
     where m.source = p_source and p_plan_key is not null
       and ((m.match_mode = 'exact' and m.plan_key = p_plan_key)
         or (m.match_mode = 'contains' and upper(p_plan_key) like '%' || upper(m.plan_key) || '%'))
     order by (m.match_mode = 'exact') desc, length(m.plan_key) desc limit 1;
    if new_tier is null then
      result := 'unmapped_plan'; new_tier := prof.tier; notes := jsonb_build_object('reason','plan not mapped','plan_key',p_plan_key);
    end if;
  else
    select setting_value into downgrade from public.admin_settings where setting_key = 'bw_downgrade_on';
    downgrade := coalesce(downgrade, '["payment_failed","canceled","expired","refunded"]'::jsonb);
    new_tier := case when downgrade ? p_kind then 'free' else prof.tier end;
  end if;

  update public.profiles set
    tier = new_tier, billing_provider = p_source,
    billing_customer_ref = coalesce(p_customer_ref, billing_customer_ref),
    billing_subscription_ref = coalesce(p_subscription_ref, billing_subscription_ref),
    billing_plan_key = case when p_kind in ('activated','renewed') then coalesce(p_plan_key, billing_plan_key) else billing_plan_key end,
    billing_status = new_status, subscription_status = new_status, billing_updated_at = p_occurred_at
  where id = prof.id;
  update public.billing_events set profile_id = prof.id, processing_status = case when result = 'applied' then 'success' else 'partial' end,
         processing_notes = notes, processed_at = now() where id = ev;
  return result;
end $$;

create or replace function public.bw_unmatched_events() returns bigint
language sql stable security definer set search_path = '' as $$
  select count(*) from public.billing_events where processing_status in ('partial','failed') and not alerted
$$;

-- A buyer can pay before having an account (no free trial: the first payment starts on the business's own site).
-- bw_apply_event records such an event as 'unmatched' and never creates users. When the buyer's email is confirmed,
-- apply those stored events, oldest first, to the new profile. Each stored row is kept for audit with its external_id
-- freed, so the event is then applied under its own id (a later redelivery is a duplicate). Events stored before
-- 'replay' existed fall back to the flat fields of the webhook body. Returns the number of events replayed.
create or replace function public.bw_replay_unmatched(p_profile uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare prof public.profiles; r record; n integer := 0; rp jsonb;
begin
  select * into prof from public.profiles where id = p_profile;
  if not found or prof.email is null then return 0; end if;
  for r in
    select id, source, external_id, event_type, raw_payload, processing_notes, created_at
      from public.billing_events
     where processing_status = 'partial' and processing_notes ->> 'reason' = 'no matching profile'
       and lower(coalesce(processing_notes #>> '{replay,email}', raw_payload ->> 'email')) = lower(prof.email)
     order by coalesce((processing_notes #>> '{replay,occurred_at}')::timestamptz, created_at), created_at
  loop
    rp := coalesce(r.processing_notes -> 'replay', '{}'::jsonb);
    update public.billing_events set external_id = r.external_id || '#unmatched-' || r.id, profile_id = prof.id,
           processing_status = 'success', processing_notes = jsonb_build_object('reason','replayed after the buyer confirmed their email'), processed_at = now()
     where id = r.id;
    perform public.bw_apply_event(
      r.source, r.external_id, r.event_type, r.raw_payload,
      coalesce(rp ->> 'customer_ref', r.raw_payload ->> 'customer_id'),
      coalesce(rp ->> 'subscription_ref', r.raw_payload ->> 'subscription_id'),
      coalesce(rp ->> 'plan_key', r.raw_payload ->> 'plan_key', r.raw_payload ->> 'product_name', r.raw_payload ->> 'product_sku'),
      prof.email,
      coalesce((rp ->> 'occurred_at')::timestamptz, r.created_at));
    n := n + 1;
  end loop;
  return n;
end $$;

-- Fires when a user is created already confirmed, or when an existing user confirms their email (a code sign-in creates
-- the user first and confirms on verifying the code). Trigger names sort after on_auth_user_created, which makes the
-- profile on insert; keep that order.
create or replace function public.bw_replay_on_confirm() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email_confirmed_at is not null and new.email is not null and (tg_op = 'INSERT' or old.email_confirmed_at is null) then
    perform public.bw_replay_unmatched(new.id);
  end if;
  return new;
end $$;
drop trigger if exists on_auth_user_replay_billing on auth.users;
create trigger on_auth_user_replay_billing after insert or update of email_confirmed_at on auth.users
  for each row execute function public.bw_replay_on_confirm();
