begin;
do $$
declare a uuid; b uuid; s uuid; i uuid;
begin
  a := t.make_user('owner@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  insert into public.it_items (subject_id, kind, title, url) values (s, 'note', 'First', 'https://example.test/x') returning id into i;
  perform t.assert(t.denied('insert into public.it_items (subject_id, kind, title) values (''' || s || ''', ''Bad Kind'', ''x'')'), 'kind must be a lowercase slug');
  perform t.assert(t.denied('insert into public.it_items (subject_id, kind, title, url) values (''' || s || ''', ''note'', ''x'', ''javascript:alert(1)'')'), 'only http(s) urls');
  perform t.assert(t.denied('update public.it_items set kind = ''other'' where id = ''' || i || ''''), 'kind is immutable for clients');
  perform t.assert(t.denied('update public.it_items set subject_id = gen_random_uuid() where id = ''' || i || ''''), 'subject_id is immutable for clients');
  insert into public.it_item_events (item_id, subject_id, kind, note) values (i, s, 'note', 'hello');
  perform t.assert(t.denied('insert into public.it_item_events (item_id, subject_id, kind) values (''' || i || ''', ''' || s || ''', ''status_change'')'), 'clients cannot forge status_change events');
  perform t.assert(t.denied('insert into public.it_item_events (item_id, subject_id, kind) values (''' || i || ''', ''' || s || ''', ''system'')'), 'clients cannot forge system events');
  perform t.assert(t.denied('update public.it_item_events set note = ''edited'''), 'events are append-only');
  perform t.assert(t.denied('delete from public.it_item_events'), 'events cannot be deleted by clients');
  perform t.assert(t.denied('select public.it_log_event(''' || i || ''', ''system'', ''x'')'), 'it_log_event is not callable by API users');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.it_items') = 0 and t.rows('select 1 from public.it_item_events') = 0, 'other users see nothing');
  perform t.assert(t.denied('insert into public.it_items (subject_id, kind, title) values (''' || s || ''', ''note'', ''intruder'')'), 'cannot add items to a foreign subject');
  perform t.assert(t.denied('insert into public.it_item_events (item_id, subject_id, kind) values (''' || i || ''', ''' || s || ''', ''note'')'), 'cannot log events on foreign items');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.it_items'), 'anon denied');
  -- plan cap
  perform t.as_admin();
  update public.admin_settings set setting_value = jsonb_set(coalesce(setting_value, '{}'::jsonb), '{free,it_max_items}', '2') where setting_key = 'plan_limits';
  insert into public.admin_settings (setting_key, setting_value) select 'plan_limits', '{"free":{"it_max_items":2}}'::jsonb where not exists (select 1 from public.admin_settings where setting_key = 'plan_limits');
  perform t.as_user(a);
  insert into public.it_items (subject_id, kind, title) values (s, 'note', 'Second');
  perform t.assert(t.denied('insert into public.it_items (subject_id, kind, title) values (''' || s || ''', ''note'', ''Third'')'), 'plan cap enforced for users');
  update public.it_items set archived_at = now() where subject_id = s and title = 'Second';
  insert into public.it_items (subject_id, kind, title) values (s, 'note', 'Third after archive');
  perform t.as_admin();
  perform set_config('request.jwt.claim.sub', '', true);  -- a real service-role request carries no user sub
  perform t.as_service();
  insert into public.it_items (subject_id, kind, title) values (s, 'note', 'service role is exempt'), (s, 'note', 'and again');
  perform t.assert(t.rows('select 1 from public.it_items where subject_id = ''' || s || '''') = 5, 'service role bypasses the cap');
  perform public.it_log_event(i, 'system', 'server note');
  perform t.assert(t.rows('select 1 from public.it_item_events where kind = ''system''') = 1, 'server can write system events');
end $$;
rollback;
