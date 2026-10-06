-- Suite for youtube-content 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; d uuid; d2 uuid; m uuid;
begin
  a := t.make_user('ytc-a@example.test'); b := t.make_user('ytc-b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  -- ytc_pieces
  perform t.as_user(a);
  perform t.assert(t.denied('select public.ytc_record(''' || s || ''', ''' || a || ''', ''ext-1'', ''https://www.youtube.com/watch?v=abc'', ''Intro video'', ''en'', ''hello'', ''a greeting'', ''{"posts":["a"]}''::jsonb)'), 'users cannot call ytc_record');
  perform t.as_service();
  d := public.ytc_record(s, a, 'ext-1', 'https://www.youtube.com/watch?v=abc', 'Intro video', 'en', 'hello', 'a greeting', '{"posts":["a"]}'::jsonb);
  perform t.assert(d = public.ytc_record(s, a, 'ext-1', 'https://www.youtube.com/watch?v=abc', 'Intro video', 'en', 'hello', 'a greeting', '{"posts":["a"]}'::jsonb), 'a replayed record returns the same item');
  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || d || ''' and kind = ''youtube_content''') = 1, 'record creates the base item');
  perform t.assert((select cost = 0 and charge_key is null from public.ytc_pieces where item_id = d), 'no charge by default');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || d || '''') = 0, 'no core credits touched');
  d2 := public.ytc_record(s, a, 'ext-2', 'https://www.youtube.com/watch?v=abc', 'Intro video', 'en', 'hello', 'a greeting', '{"posts":["a"]}'::jsonb, 1);
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''ytc:' || d2 || ''' and amount > 0') = 1, 'a positive cost is charged in the same transaction');
  perform t.assert(t.denied('select public.ytc_record(''' || s || ''', ''' || a || ''', ''ext-3'', ''https://www.youtube.com/watch?v=abc'', ''Intro video'', ''en'', ''hello'', ''a greeting'', ''{"posts":["a"]}''::jsonb, 1000000000)'), 'an unaffordable cost is refused');
  perform t.assert(t.denied('select public.ytc_record(''' || s || ''', ''' || b || ''', ''ext-4'', ''https://www.youtube.com/watch?v=abc'', ''Intro video'', ''en'', ''hello'', ''a greeting'', ''{"posts":["a"]}''::jsonb)'), 'recording for a user without subject access is refused');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.ytc_pieces') = 0, 'other users see no records');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.ytc_pieces'), 'anon denied');
end $$;
rollback;
