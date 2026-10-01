begin;
do $$
declare a uuid; adm uuid; n int; c bigint;
begin
  a := t.make_user('human@example.test'); adm := t.make_user('ops@example.test');
  perform t.as_admin();
  update public.profiles set is_admin = true where id = adm;
  perform t.as_service();
  perform public.ts_record_failure('signup', repeat('a', 32), 'timeout-or-duplicate', a);
  perform public.ts_record_failure('signup', repeat('a', 32), 'invalid-input-response');
  select public.ts_recent_failures(repeat('a', 32)) into c;
  perform t.assert(c = 2, 'recent failures counted per ip hash');
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.ts_failures') = 0, 'ordinary users cannot read the failure log');
  perform t.assert(t.denied('insert into public.ts_failures (action, ip_hash, reason) values (''x.y'', repeat(''b'',32), ''r'')'), 'users cannot write the log');
  perform t.assert(t.denied('select public.ts_record_failure(''a.b'', repeat(''c'',32), ''r'')'), 'users cannot call record');
  perform t.assert(t.denied('select public.ts_purge_old(1)'), 'users cannot purge');
  perform t.as_user(adm);
  perform t.assert(t.rows('select 1 from public.ts_failures') = 2, 'admins can read the log');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.ts_failures'), 'anon denied');
  perform t.as_service();
  update public.ts_failures set created_at = now() - interval '40 days' where reason = 'invalid-input-response';
  select public.ts_purge_old(30) into c;
  perform t.assert(c = 1, 'purge removes only rows past retention');
end $$;
rollback;
