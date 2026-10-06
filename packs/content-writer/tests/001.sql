-- Suite for content-writer 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; d uuid; d2 uuid; m uuid;
begin
  a := t.make_user('cwr-a@example.test'); b := t.make_user('cwr-b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  -- cwr_pieces
  perform t.as_user(a);
  perform t.assert(t.denied('select public.cwr_record(''' || s || ''', ''' || a || ''', ''ext-1'', ''Winter skincare'', ''friendly'', ''first person'', 500, ''Some text.'')'), 'users cannot call cwr_record');
  perform t.as_service();
  d := public.cwr_record(s, a, 'ext-1', 'Winter skincare', 'friendly', 'first person', 500, 'Some text.');
  perform t.assert(d = public.cwr_record(s, a, 'ext-1', 'Winter skincare', 'friendly', 'first person', 500, 'Some text.'), 'a replayed record returns the same item');
  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || d || ''' and kind = ''content_piece''') = 1, 'record creates the base item');
  perform t.assert((select cost = 0 and charge_key is null from public.cwr_pieces where item_id = d), 'no charge by default');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || d || '''') = 0, 'no core credits touched');
  d2 := public.cwr_record(s, a, 'ext-2', 'Winter skincare', 'friendly', 'first person', 500, 'Some text.', 1);
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''cwr:' || d2 || ''' and amount > 0') = 1, 'a positive cost is charged in the same transaction');
  perform t.assert(t.denied('select public.cwr_record(''' || s || ''', ''' || a || ''', ''ext-3'', ''Winter skincare'', ''friendly'', ''first person'', 500, ''Some text.'', 1000000000)'), 'an unaffordable cost is refused');
  perform t.assert(t.denied('select public.cwr_record(''' || s || ''', ''' || b || ''', ''ext-4'', ''Winter skincare'', ''friendly'', ''first person'', 500, ''Some text.'')'), 'recording for a user without subject access is refused');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.cwr_pieces') = 0, 'other users see no records');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.cwr_pieces'), 'anon denied');
end $$;
rollback;
