begin;
do $$
declare a uuid; adm uuid; b uuid; c uuid; r text; tr text; st text; base bigint; n integer;
begin
  a := t.make_user('buyer@example.test'); adm := t.make_user('ops@example.test');
  perform t.as_admin();
  update public.profiles set is_admin = true where id = adm;
  perform t.as_user(adm);
  insert into public.bw_plan_map (source, plan_key, tier, updated_by) values ('webstore', 'pro-monthly', 'pro', adm);
  insert into public.bw_plan_map (source, plan_key, tier, match_mode, updated_by) values ('wootest', 'pro', 'pro', 'contains', adm), ('wootest', 'pro plus', 'pro_plus', 'contains', adm);
  perform t.assert(t.denied('insert into public.bw_plan_map (source, plan_key, tier, updated_by) values (''x'', ''y'', ''z'', ''' || a || ''')'), 'plan map rows must be attributed to the acting admin');
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.bw_plan_map') = 0, 'non-admins cannot read the plan map');
  perform t.assert(t.denied('insert into public.bw_plan_map (source, plan_key, tier, updated_by) values (''webstore'', ''x'', ''enterprise'', ''' || a || ''')'), 'non-admins cannot map plans to tiers');
  perform t.assert(t.denied('select public.bw_apply_event(''webstore'', ''e0'', ''activated'', ''{}'')'), 'users cannot apply billing events');
  perform t.assert(t.denied('update public.profiles set tier = ''pro'' where id = ''' || a || ''''), 'users cannot self-upgrade');
  perform t.as_anon();
  perform t.assert(t.denied('select public.bw_apply_event(''webstore'', ''e0'', ''activated'', ''{}'')'), 'anon cannot apply billing events');
  perform t.as_service();
  base := public.bw_unmatched_events();
  r := public.bw_apply_event('webstore', 'e1', 'activated', '{"o":1}', 'cust1', 'sub1', 'pro-monthly', 'Buyer@Example.test', now() - interval '1 hour');
  perform t.assert(r = 'applied', 'activation by email applies: ' || r);
  select tier || '/' || billing_status into tr from public.profiles where id = a;
  perform t.assert(tr = 'pro/active', 'tier pro and active: ' || tr);
  perform t.assert(public.bw_apply_event('webstore', 'e1', 'activated', '{}') = 'duplicate', 'same external id is a duplicate');
  perform t.assert(public.bw_apply_event('webstore', 'e2', 'payment_failed', '{}', null, 'sub1', null, null, now() - interval '30 minutes') = 'applied', 'payment_failed applies via subscription ref');
  select tier || '/' || billing_status into tr from public.profiles where id = a;
  perform t.assert(tr = 'free/past_due', 'default policy drops to free on payment failure: ' || tr);
  perform t.assert(public.bw_apply_event('webstore', 'e2b', 'renewed', '{}', null, 'sub1', 'pro-monthly', null, now() - interval '20 minutes') = 'applied', 'renewal restores the tier');
  perform t.as_admin();
  insert into public.admin_settings (setting_key, setting_value) values ('bw_downgrade_on', '["expired"]') on conflict (setting_key) do update set setting_value = excluded.setting_value;
  perform t.as_service();
  perform public.bw_apply_event('webstore', 'e2c', 'payment_failed', '{}', null, 'sub1', null, null, now() - interval '10 minutes');
  select tier || '/' || billing_status into tr from public.profiles where id = a;
  perform t.assert(tr = 'pro/past_due', 'admin setting can keep access during payment failure: ' || tr);
  perform t.assert(public.bw_apply_event('wootest', 'w1', 'activated', '{}', 'wc9', 'sub1', 'Acme Pro Plus Yearly', 'buyer@example.test', now() - interval '5 minutes') = 'applied', 'woo product name matches');
  select tier into tr from public.profiles where id = a;
  perform t.assert(tr = 'pro_plus', 'longest contains-match wins (pro_plus over pro): ' || tr);
  perform t.assert(public.bw_apply_event('webstore', 'e3', 'renewed', '{}', null, 'sub1', 'pro-monthly', null, now() - interval '2 hours') = 'stale', 'older event is ignored');
  perform t.assert(public.bw_apply_event('webstore', 'e4', 'renewed', '{}', null, 'sub1', 'mystery-plan', null, now()) = 'unmapped_plan', 'unmapped plan flagged');
  select tier into tr from public.profiles where id = a;
  perform t.assert(tr = 'pro_plus', 'unmapped plan does not change tier');
  perform t.assert(public.bw_apply_event('webstore', 'e5', 'activated', '{}', 'nobody', null, 'pro-monthly', 'ghost@example.test') = 'unmatched', 'unknown customer is recorded as unmatched');
  perform t.assert(public.bw_unmatched_events() - base = 2, 'health check counts partial events');
  perform t.assert(public.bw_apply_event('webstore', 'e6', 'expired', '{}', null, 'sub1') = 'applied', 'expiry applies');
  select tier || '/' || billing_status into tr from public.profiles where id = a;
  perform t.assert(tr = 'free/expired', 'expired returns to free: ' || tr);
  select processing_status into st from public.billing_events where external_id = 'e3';
  perform t.assert(st = 'success', 'stale events are closed out, not left pending');

  -- Paying before having an account: stored as unmatched, applied when the buyer confirms their email.
  perform t.as_admin();
  perform t.assert(public.bw_apply_event('webstore', 'late1', 'activated', '{"email":"late@example.test"}', 'custL', 'subL', 'pro-monthly', 'Late@Example.test', now() - interval '3 hours') = 'unmatched', 'payment before signup is unmatched');
  perform t.assert(public.bw_apply_event('webstore', 'late2', 'renewed', '{"email":"late@example.test"}', 'custL', 'subL', 'pro-monthly', 'late@example.test', now() - interval '2 hours') = 'unmatched', 'second event before signup is unmatched');
  b := gen_random_uuid();
  -- a code sign-in creates the user before the code is verified: an unconfirmed email must not claim the payment
  insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'late@example.test', '{}', '{}', now(), now());
  select tier into tr from public.profiles where id = b;
  perform t.assert(tr = 'free', 'unconfirmed email does not claim a stored payment: ' || tr);
  update auth.users set email_confirmed_at = now() where id = b;
  select tier || '/' || billing_status into tr from public.profiles where id = b;
  perform t.assert(tr = 'pro/active', 'stored payments apply once the email is confirmed: ' || tr);
  perform t.assert(public.bw_apply_event('webstore', 'late1', 'activated', '{}') = 'duplicate', 'a redelivery after replay is a duplicate');
  select count(*) into n from public.billing_events where external_id like 'late1#unmatched-%' and processing_status = 'success' and profile_id = b;
  perform t.assert(n = 1, 'the unmatched row is kept for audit and closed out');
  select count(*) into n from public.billing_events where external_id in ('late1', 'late2') and processing_status = 'success' and profile_id = b;
  perform t.assert(n = 2, 'both events were applied to the new profile: ' || n);
  perform t.assert(public.bw_replay_unmatched(b) = 0, 'replay is idempotent');
  -- a user created already confirmed gets the same treatment
  perform public.bw_apply_event('webstore', 'late3', 'activated', '{"email":"conf@example.test"}', 'custC', 'subC', 'pro-monthly', 'conf@example.test', now() - interval '1 hour');
  c := gen_random_uuid();
  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'conf@example.test', now(), '{}', '{}', now(), now());
  select tier || '/' || billing_status into tr from public.profiles where id = c;
  perform t.assert(tr = 'pro/active', 'a user created confirmed gets the stored payment: ' || tr);
  perform t.as_user(c);
  perform t.assert(t.denied('select public.bw_replay_unmatched(''' || c || ''')'), 'users cannot call the replay');
end $$;
rollback;
