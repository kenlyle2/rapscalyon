-- Suite for interior-designs 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; d uuid; d2 uuid; n bigint; used1 integer; used2 integer;
begin
  a := t.make_user('designer@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  d := public.idg_request_design(s, 'airy and bright', 'living room', 'scandinavian', 'uploads/a/room.png');
  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || d || ''' and kind = ''interior_design''') = 1, 'request creates the base item');
  perform t.assert((select status = 'queued' and cost >= 0 from public.idg_designs where item_id = d), 'job starts queued with its cost');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''idg:' || d || ''' and amount > 0') = 1, 'credits charged at request time');
  perform t.assert(t.denied('insert into public.idg_designs (item_id, subject_id, requested_by, prompt, room_type, theme, ref_image_key, cost, charge_key) values (gen_random_uuid(), ''' || s || ''', ''' || a || ''', ''x'', ''x'', ''x'', ''a.png'', 0, ''k'')'), 'clients cannot insert jobs directly');
  perform t.assert(t.denied('update public.idg_designs set status = ''succeeded'' where item_id = ''' || d || ''''), 'clients cannot update jobs');
  perform t.assert(t.denied('select public.idg_request_design(''' || s || ''', ''x'', ''kitchen'', ''modern'', ''../etc/passwd'')'), 'reference key traversal refused');
  perform t.assert(t.denied('select public.idg_mark_started(''' || d || ''', ''p1'')'), 'users cannot call executor functions');
  perform t.assert(t.denied('select public.idg_fail(''' || d || ''', ''x'')'), 'users cannot fail jobs');
  -- executor path
  perform t.as_service();
  perform t.assert(public.idg_mark_started(d, 'pred-1'), 'start moves queued to processing');
  perform t.assert(not public.idg_mark_started(d, 'pred-2'), 'a second start is a no-op');
  perform t.assert(public.idg_complete(d, array['out/a/1.png']), 'complete succeeds once');
  perform t.assert(not public.idg_complete(d, array['out/a/other.png']), 'a replayed completion changes nothing');
  perform t.assert(not public.idg_fail(d, 'late failure'), 'a finished job cannot be failed or refunded');
  perform t.assert((select image_keys = array['out/a/1.png'] from public.idg_designs where item_id = d), 'result keys stored');
  -- failure refunds exactly once
  perform t.as_user(a);
  d2 := public.idg_request_design(s, 'dark and moody', 'bedroom', 'industrial', 'uploads/a/room2.png');
  perform t.as_service();
  perform t.assert(public.idg_fail(d2, 'model error'), 'fail marks the job failed');
  perform t.assert(not public.idg_fail(d2, 'model error again'), 'a replayed failure is a no-op');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''idg:' || d2 || ':refund''') = 1 or (select cost = 0 from public.idg_designs where item_id = d2), 'exactly one refund');
  -- designs recorded from an outside generator: no core charge, idempotent, access-checked
  perform t.as_user(a);
  perform t.assert(t.denied('select public.idg_record_design(''' || s || ''', ''' || a || ''', ''ext-1'', ''p'', ''kitchen'', ''modern'', null, array[''out/a/x.png''])'), 'users cannot call idg_record_design');
  perform t.as_service();
  d2 := public.idg_record_design(s, a, 'ext-1', 'warm kitchen', 'kitchen', 'modern', null, array['out/a/x.png']);
  perform t.assert(d2 = public.idg_record_design(s, a, 'ext-1', 'warm kitchen', 'kitchen', 'modern', null, array['out/a/x.png']), 'a replayed record returns the same item');
  perform t.assert((select status = 'succeeded' and cost = 0 and charge_key is null from public.idg_designs where item_id = d2), 'external design is succeeded with no charge');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || d2 || '''') = 0, 'no core credits touched');
  perform t.assert(t.denied('select public.idg_record_design(''' || s || ''', ''' || b || ''', ''ext-2'', ''p'', ''kitchen'', ''modern'', null, null)'), 'recording for a user without subject access is refused');
  -- isolation
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.idg_designs') = 0, 'other users see no jobs');
  perform t.assert(t.denied('select public.idg_request_design(''' || s || ''', ''x'', ''kitchen'', ''modern'', ''a.png'')'), 'cannot request into a foreign subject');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.idg_designs'), 'anon denied');
  perform t.assert(t.denied('select public.idg_request_design(''' || s || ''', ''x'', ''kitchen'', ''modern'', ''a.png'')'), 'anon cannot request');
end $$;
rollback;
