-- Maps a provider's plan/product key to an app tier. Admin-managed.
create table public.bw_plan_map (
  source      text not null check (source ~ '^[a-z][a-z0-9_-]{1,31}$'),
  plan_key    text not null check (length(plan_key) between 1 and 100),
  tier        text not null check (tier ~ '^[a-z][a-z0-9_-]{1,31}$'),
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (source, plan_key)
);
create index bw_plan_map_updated_by_idx on public.bw_plan_map (updated_by) where updated_by is not null;
create trigger bw_plan_map_updated_at before update on public.bw_plan_map for each row execute function public.set_updated_at();

alter table public.bw_plan_map enable row level security;
create policy bw_plan_map_select on public.bw_plan_map for select to authenticated using ((select public.is_admin()));
create policy bw_plan_map_insert on public.bw_plan_map for insert to authenticated with check ((select public.is_admin()) and updated_by = (select auth.uid()));
create policy bw_plan_map_update on public.bw_plan_map for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()) and updated_by = (select auth.uid()));
create policy bw_plan_map_delete on public.bw_plan_map for delete to authenticated using ((select public.is_admin()));
select public.apply_mfa_gate('public.bw_plan_map');
grant select, delete on public.bw_plan_map to authenticated;
grant insert (source, plan_key, tier, updated_by) on public.bw_plan_map to authenticated;
grant update (tier, updated_by) on public.bw_plan_map to authenticated;

-- Apply one normalized provider event. The app-layer adapter verifies the webhook signature and normalizes:
--   p_kind: activated | renewed | payment_failed | canceled | expired | refunded
-- Idempotent on (source, external_id). Returns: applied | duplicate | stale | unmatched | unmapped_plan
create function public.bw_apply_event(
  p_source text, p_external_id text, p_kind text, p_payload jsonb,
  p_customer_ref text default null, p_subscription_ref text default null,
  p_plan_key text default null, p_email text default null, p_occurred_at timestamptz default now()
) returns text
language plpgsql security definer set search_path = '' as $$
declare ev uuid; prof public.profiles; new_tier text; new_status text; result text := 'applied'; notes jsonb := '{}'::jsonb;
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
    update public.billing_events set processing_status = 'partial', processing_notes = jsonb_build_object('reason','no matching profile'), processed_at = now() where id = ev;
    return 'unmatched';
  end if;

  if prof.billing_updated_at is not null and prof.billing_updated_at > p_occurred_at then
    update public.billing_events set profile_id = prof.id, processing_status = 'success', processing_notes = jsonb_build_object('reason','stale event ignored'), processed_at = now() where id = ev;
    return 'stale';
  end if;

  new_status := case p_kind when 'activated' then 'active' when 'renewed' then 'active' when 'payment_failed' then 'past_due'
                            when 'canceled' then 'canceled' else 'expired' end;
  if p_kind in ('activated','renewed') then
    select tier into new_tier from public.bw_plan_map where source = p_source and plan_key = p_plan_key;
    if new_tier is null then
      result := 'unmapped_plan'; new_tier := prof.tier; notes := jsonb_build_object('reason','plan not mapped','plan_key',p_plan_key);
    end if;
  elsif p_kind in ('expired','refunded') then
    new_tier := 'free';
  else
    new_tier := prof.tier;  -- payment_failed / canceled keep access until the provider says expired
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

create function public.bw_unmatched_events() returns bigint
language sql stable security definer set search_path = '' as $$
  select count(*) from public.billing_events where processing_status in ('partial','failed') and not alerted
$$;
