begin;
do $$
declare a uuid; b uuid; s uuid; sb uuid;
begin
  a := t.make_user('a@example.test'); b := t.make_user('b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Alice') returning id into s;
  perform t.assert(t.denied('insert into public.subjects (owner_id, kind, name) values (''' || a || ''', ''individual'', ''Second'')'), 'ind_max_subjects default 1 enforced');
  perform t.assert(not t.denied('insert into public.subjects (owner_id, kind, name) values (''' || a || ''', ''business'', ''Shop'')'), 'limit applies to individuals only');
  insert into public.ind_details (subject_id, headline, links) values (s, 'Engineer', '["https://x.test"]');
  perform t.assert(t.denied('insert into public.ind_details (subject_id, links) values (''' || s || ''', ''{}'')'), 'links must be a JSON array');
  perform t.assert(t.denied('update public.ind_details set subject_id = gen_random_uuid() where subject_id = ''' || s || ''''), 'subject_id is not updatable');
  select id into sb from public.subjects where kind = 'business' and owner_id = a;
  perform t.assert(t.denied('insert into public.ind_details (subject_id) values (''' || sb || ''')'), 'details only for individual subjects');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.ind_details') = 0, 'other users cannot see details');
  perform t.assert(t.denied('insert into public.ind_details (subject_id) values (''' || s || ''')'), 'other users cannot add details to a foreign subject');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.ind_details'), 'anon denied');
  perform t.as_service();
  insert into public.admin_settings (setting_key, setting_value) values ('plan_limits', '{"pro":{"ind_max_subjects":3}}');
  update public.profiles set tier = 'pro' where id = a;
  perform t.as_user(a);
  perform t.assert(not t.denied('insert into public.subjects (owner_id, kind, name) values (''' || a || ''', ''individual'', ''Second'')'), 'plan limit raises with tier');
end $$;
rollback;
