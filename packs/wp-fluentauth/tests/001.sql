begin;
do $$
declare a uuid; b uuid; adm uuid; n bigint;
begin
  a := t.make_user('wf-a@example.test'); b := t.make_user('wf-b@example.test');
  adm := t.make_user('wf-ops@example.test');
  perform t.as_admin();
  update public.profiles set is_admin = true where id = adm;
  perform t.as_service();
  perform public.wf_record_handoff(a);
  n := public.wf_record_handoff(a);
  perform t.assert(n = 2, 'second handoff increments the counter');
  perform public.wf_record_handoff(b);
  perform t.assert(t.rows('select 1 from public.wf_handoffs where profile_id in (''' || a || ''',''' || b || ''')') = 2, 'one row per profile');
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.wf_handoffs') = 0, 'users cannot read the handoff log');
  perform t.assert(t.denied('insert into public.wf_handoffs (profile_id) values (gen_random_uuid())'), 'users cannot insert');
  perform t.assert(t.denied('update public.wf_handoffs set handoffs = 99'), 'users cannot update');
  perform t.assert(t.denied('delete from public.wf_handoffs'), 'users cannot delete');
  perform t.assert(t.denied('select public.wf_record_handoff(''' || a || ''')'), 'the writer is not callable by API users');
  perform t.as_user(adm);
  perform t.assert(t.rows('select 1 from public.wf_handoffs where profile_id in (''' || a || ''',''' || b || ''')') = 2, 'admins can read the log');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.wf_handoffs'), 'anon denied');
  perform t.assert(t.denied('select public.wf_record_handoff(gen_random_uuid())'), 'anon cannot call the writer');
end $$;
rollback;
