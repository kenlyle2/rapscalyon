begin;
do $$
declare a uuid; b uuid;
begin
  a := t.make_user('private@example.test'); b := t.make_user('other@example.test');
  perform t.as_service();
  perform t.assert(public.ph_may_track(a), 'default: analytics allowed');
  perform t.assert(not public.ph_may_track(a, 'replay'), 'default: replay not allowed');
  perform t.as_user(a);
  insert into public.ph_consent (profile_id, analytics, session_replay) values (a, false, true);
  perform t.assert(t.denied('insert into public.ph_consent (profile_id) values (''' || b || ''')'), 'cannot set another user''s consent');
  perform t.assert(t.denied('select public.ph_may_track(''' || b || ''')'), 'users cannot call the server gate');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.ph_consent') = 0, 'consent is private');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.ph_consent'), 'anon denied');
  perform t.as_service();
  perform t.assert(not public.ph_may_track(a), 'opt-out blocks analytics');
  perform t.assert(not public.ph_may_track(a, 'replay'), 'replay requires analytics too');
end $$;
rollback;
