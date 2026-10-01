begin;
select t.assert(to_regclass('public.profiles') is not null, 'core installed');
do $$
declare a uuid; b uuid; adm uuid; s uuid; r jsonb; n int;
begin
  a := t.make_user('a@example.test'); b := t.make_user('b@example.test'); adm := t.make_user('admin@example.test', true);

  -- profile auto-created, id = auth uid
  perform t.assert((select count(*) from public.profiles where id in (a, b, adm)) = 3, 'handle_new_user creates profiles');

  -- ---- anon: nothing ----
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.profiles'), 'anon cannot read profiles');
  perform t.assert(t.denied('select 1 from public.admin_settings'), 'anon cannot read admin_settings');
  perform t.assert(t.denied('select public.is_admin()'), 'anon cannot call is_admin');
  perform t.assert(t.denied('select public.charge_credits(''' || a || ''', 1, ''k'')'), 'anon cannot charge credits');
  perform t.assert(t.denied('select public.apply_mfa_gate(''public.profiles'')'), 'anon cannot call apply_mfa_gate');

  -- ---- user a ----
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.profiles') = 1, 'user sees only own profile');
  perform t.assert(not t.denied('update public.profiles set display_name = ''A'' where id = ''' || a || ''''), 'user can edit display_name');
  perform t.assert(t.denied('update public.profiles set is_admin = true where id = ''' || a || ''''), 'user cannot self-promote');
  perform t.assert(t.denied('update public.profiles set tier = ''pro'' where id = ''' || a || ''''), 'user cannot change tier');
  perform t.assert(t.denied('update public.profiles set usage_daily = 0 where id = ''' || a || ''''), 'user cannot reset usage');
  perform t.assert(t.denied('select * from public.user_credentials'), 'user cannot read credentials');
  perform t.assert(t.denied('insert into public.user_credentials (user_id, provider, data) values (''' || a || ''', ''x'', ''{}'')'), 'user cannot write credentials');
  perform t.assert(t.denied('select public.charge_credits(''' || a || ''', 1, ''k'')'), 'user cannot call charge_credits');
  perform t.assert(t.denied('select public.check_rate_limit(''k'', 1, 60)'), 'user cannot call check_rate_limit');
  perform t.assert(t.denied('insert into public.credit_usage_log (user_id, amount, daily_after, monthly_after) values (''' || a || ''', -100, 0, 0)'), 'user cannot mint credits via ledger');
  perform t.assert(t.denied('insert into public.billing_events (source, event_type, external_id, raw_payload) values (''x'',''y'',''z'',''{}'')'), 'user cannot write billing events');
  perform t.assert(t.rows('select 1 from public.admin_settings') = 0, 'non-admin sees no admin_settings rows');
  perform t.assert(t.denied('insert into public.admin_settings (setting_key, setting_value) values (''x'', ''1'')'), 'non-admin cannot write admin_settings');

  -- subjects: create, own, isolate
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Alice') returning id into s;
  perform t.assert(t.rows('select 1 from public.subjects') = 1, 'owner sees own subject');
  perform t.assert(t.denied('insert into public.subjects (owner_id, kind, name) values (''' || b || ''', ''individual'', ''Spoof'')'), 'cannot create subject for someone else');
  perform t.assert(t.denied('update public.subjects set owner_id = ''' || b || ''' where id = ''' || s || ''''), 'cannot transfer subject ownership');
  perform t.assert(t.denied('insert into public.subject_members (subject_id, user_id, accepted_at) values (''' || s || ''', ''' || a || ''', now())'), 'cannot self-add membership');

  -- ---- user b cannot see a's data ----
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.subjects') = 0, 'other user sees no foreign subjects');
  perform t.assert(t.rows('select 1 from public.profiles') = 1, 'b sees only own profile');
  perform t.assert(not public.has_subject_access(s), 'b has no access to a''s subject');

  -- ---- membership grants access ----
  perform t.as_service();
  insert into public.subject_members (subject_id, user_id, role, accepted_at) values (s, b, 'member', now());
  perform t.as_user(b);
  perform t.assert(public.has_subject_access(s), 'accepted member has access');
  perform t.assert(t.rows('select 1 from public.subjects') = 1, 'member sees shared subject');
  update public.subjects set name = 'hijack' where id = s;
  perform t.assert(t.rows('select 1 from public.subjects where name = ''hijack''') = 0, 'member cannot rename (owner only)');

  -- ---- admin ----
  perform t.as_user(adm);
  perform t.assert(t.rows('select 1 from public.profiles') >= 3, 'admin sees all profiles');
  perform t.assert(not t.denied('insert into public.admin_settings (setting_key, setting_value) values (''plan_limits'', ''{"free":{"daily":2,"monthly":3}}'')'), 'admin can write admin_settings');

  -- ---- credits (service) ----
  perform t.as_service();
  r := public.charge_credits(a, 1, 'op1', 'test');
  perform t.assert((r->>'success')::boolean and (r->>'daily')::int = 1, 'first charge ok');
  r := public.charge_credits(a, 1, 'op1', 'test');
  perform t.assert((r->>'duplicate')::boolean and (r->>'daily')::int = 1, 'idempotent replay does not double charge');
  r := public.charge_credits(a, 1, 'op2', 'test');
  perform t.assert((r->>'success')::boolean and (r->>'daily')::int = 2, 'second charge ok');
  r := public.charge_credits(a, 1, 'op3', 'test');
  perform t.assert(r->>'error' = 'DAILY_LIMIT_EXCEEDED', 'daily limit enforced from plan_limits (2)');
  r := public.charge_credits(a, -1, 'op1:refund', 'test');
  perform t.assert((r->>'success')::boolean and (r->>'daily')::int = 1, 'refund of a real charge works');
  r := public.charge_credits(a, -1, 'op1:refund', 'test');
  perform t.assert((r->>'duplicate')::boolean, 'refund is idempotent');
  r := public.charge_credits(a, -5, 'nothing:refund', 'test');
  perform t.assert(r->>'error' = 'NO_MATCHING_CHARGE', 'cannot refund a charge that never happened');
  r := public.charge_credits(a, -1, 'op2', 'test');
  perform t.assert(r->>'error' = 'REFUND_KEY_INVALID' or r->>'duplicate' = 'true', 'refund must use :refund key');
  r := public.charge_credits(a, 1, null, 'test');
  perform t.assert(r->>'error' = 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency key required');
  -- window rollover: pretend the usage was yesterday
  update public.profiles set usage_daily_date = current_date - 1 where id = a;
  r := public.charge_credits(a, 1, 'op4', 'test');
  perform t.assert((r->>'success')::boolean and (r->>'daily')::int = 1, 'daily counter resets on a new day and is written back');
  perform t.assert((select usage_daily_date from public.profiles where id = a) = current_date, 'reset date persisted');

  -- ---- rate limit ----
  perform t.assert(public.check_rate_limit('rl', 2, 60) and public.check_rate_limit('rl', 2, 60), 'within limit');
  perform t.assert(not public.check_rate_limit('rl', 2, 60), 'over limit blocked');

  -- ---- event trigger: new tables get RLS ----
  perform t.as_admin();
  create table public.zz_probe (id int);
  perform t.assert((select relrowsecurity from pg_class where oid = 'public.zz_probe'::regclass), 'ensure_rls enables RLS on new tables');
  perform t.assert(not has_table_privilege('authenticated', 'public.zz_probe', 'select'), 'new tables are default-deny');

  -- ---- MFA gate: enrolled user at aal1 is blocked ----
  perform t.as_admin();
  insert into auth.mfa_factors (id, user_id, factor_type, status, created_at, updated_at, friendly_name)
    values (gen_random_uuid(), a, 'totp', 'verified', now(), now(), 'phone');
  perform t.as_user(a, 'aal1');
  perform t.assert(t.rows('select 1 from public.subjects') = 0, 'enrolled user at aal1 is gated out');
  perform t.as_user(a, 'aal2');
  perform t.assert(t.rows('select 1 from public.subjects') = 1, 'same user at aal2 is allowed');
end $$;
rollback;
