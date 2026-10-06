-- Suite for qr-code-generations 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; d uuid; d2 uuid; m uuid;
begin
  a := t.make_user('qrg-a@example.test'); b := t.make_user('qrg-b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  -- qrg_codes
  perform t.as_user(a);
  d := public.qrg_request(s, 'a mountain village', 'https://example.test/menu');
  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || d || ''' and kind = ''qr_code''') = 1, 'request creates the base item');
  perform t.assert((select status = 'queued' and cost >= 0 from public.qrg_codes where item_id = d), 'job starts queued with its cost');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''qrg:' || d || ''' and amount > 0') = 1, 'credits charged at request time');
  perform t.assert(t.denied('update public.qrg_codes set status = ''succeeded'' where item_id = ''' || d || ''''), 'clients cannot update jobs');
  perform t.assert(t.denied('delete from public.qrg_codes where item_id = ''' || d || ''''), 'clients cannot delete jobs');
  perform t.assert(t.denied('select public.qrg_mark_started(''' || d || ''', ''p1'')'), 'users cannot call executor functions');
  perform t.assert(t.denied('select public.qrg_fail(''' || d || ''', ''x'')'), 'users cannot fail jobs');
  perform t.as_service();
  perform t.assert(public.qrg_mark_started(d, 'pred-1'), 'start moves queued to processing');
  perform t.assert(not public.qrg_mark_started(d, 'pred-2'), 'a second start is a no-op');
  perform t.assert(public.qrg_complete(d, array['out/a/1.bin']), 'complete succeeds once');
  perform t.assert(not public.qrg_complete(d, array['out/a/other.bin']), 'a replayed completion changes nothing');
  perform t.assert(not public.qrg_fail(d, 'late failure'), 'a finished job cannot be failed or refunded');
  perform t.assert((select output_keys = array['out/a/1.bin'] from public.qrg_codes where item_id = d), 'result keys stored');
  perform t.as_user(a);
  d2 := public.qrg_request(s, 'a mountain village', 'https://example.test/menu');
  perform t.as_service();
  perform t.assert(public.qrg_fail(d2, 'model error'), 'fail marks the job failed');
  perform t.assert(not public.qrg_fail(d2, 'model error again'), 'a replayed failure is a no-op');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''qrg:' || d2 || ':refund''') = 1 or (select cost = 0 from public.qrg_codes where item_id = d2), 'exactly one refund');
  perform t.as_user(a);
  perform t.assert(t.denied('select public.qrg_record(''' || s || ''', ''' || a || ''', ''ext-1'', ''a mountain village'', ''https://example.test/menu'', array[''out/a/1.bin''])'), 'users cannot call qrg_record');
  perform t.as_service();
  d2 := public.qrg_record(s, a, 'ext-1', 'a mountain village', 'https://example.test/menu', array['out/a/1.bin']);
  perform t.assert(d2 = public.qrg_record(s, a, 'ext-1', 'a mountain village', 'https://example.test/menu', array['out/a/1.bin']), 'a replayed record returns the same item');
  perform t.assert((select status = 'succeeded' and cost = 0 and charge_key is null from public.qrg_codes where item_id = d2), 'recorded item is succeeded with no charge');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || d2 || '''') = 0, 'no core credits touched');
  perform t.assert(t.denied('select public.qrg_record(''' || s || ''', ''' || b || ''', ''ext-2'', ''a mountain village'', ''https://example.test/menu'', array[''out/a/1.bin''])'), 'recording for a user without subject access is refused');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.qrg_codes') = 0, 'other users see no jobs');
  perform t.assert(t.denied('select public.qrg_request(''' || s || ''', ''a mountain village'', ''https://example.test/menu'')'), 'cannot request into a foreign subject');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.qrg_codes'), 'anon denied');
  perform t.assert(t.denied('select public.qrg_request(''' || s || ''', ''a mountain village'', ''https://example.test/menu'')'), 'anon cannot request');
end $$;
rollback;
