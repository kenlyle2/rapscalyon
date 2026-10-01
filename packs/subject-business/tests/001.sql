begin;
do $$
declare a uuid; b uuid; s uuid; sb uuid;
begin
  a := t.make_user('a@example.test'); b := t.make_user('b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Alice') returning id into s;
  perform t.assert(t.denied('insert into public.subjects (owner_id, kind, name) values (''' || a || ''', ''business'', ''Second'')'), 'biz_max_subjects default 1 enforced');
  perform t.assert(not t.denied('insert into public.subjects (owner_id, kind, name) values (''' || a || ''', ''individual'', ''Person'')'), 'limit applies to businesses only');
  insert into public.biz_details (subject_id, category, address) values (s, 'Cafe', '{"city":"Oslo"}');
  perform t.assert(t.denied('insert into public.biz_details (subject_id, address) values (''' || s || ''', ''{}'')'), 'address must be a JSON object');
  perform t.assert(t.denied('update public.biz_details set subject_id = gen_random_uuid() where subject_id = ''' || s || ''''), 'subject_id is not updatable');
  select id into sb from public.subjects where kind = 'individual' and owner_id = a;
  perform t.assert(t.denied('insert into public.biz_details (subject_id) values (''' || sb || ''')'), 'details only for business subjects');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.biz_details') = 0, 'other users cannot see details');
  perform t.assert(t.denied('insert into public.biz_details (subject_id) values (''' || s || ''')'), 'other users cannot add details to a foreign subject');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.biz_details'), 'anon denied');
  perform t.as_service();
  insert into public.admin_settings (setting_key, setting_value) values ('plan_limits', '{"pro":{"biz_max_subjects":3}}');
  update public.profiles set tier = 'pro' where id = a;
  perform t.as_user(a);
  perform t.assert(not t.denied('insert into public.subjects (owner_id, kind, name) values (''' || a || ''', ''business'', ''Second'')'), 'plan limit raises with tier');
end $$;
rollback;
