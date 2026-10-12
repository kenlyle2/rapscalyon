begin;
do $$
declare a uuid; b uuid; s uuid; s2 uuid; p uuid; e uuid; n int; id1 uuid; id2 uuid;
begin
  a := t.make_user('owner@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Studio') returning id into s;
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Second') returning id into s2;
  insert into public.ppl_people (subject_id, created_by, name) values (s, a, 'Casey') returning id into p;

  insert into public.cal_events (subject_id, created_by, person_id, title, starts_at, ends_at) values (s, a, p, 'Intro session', now(), now() + interval '1 hour') returning id into e;
  perform t.assert(t.rows('select 1 from public.cal_events') = 1, 'owner sees their event');
  perform t.assert(t.denied('insert into public.cal_events (subject_id, created_by, title, starts_at, ends_at) values (''' || s || ''', ''' || a || ''', ''Bad'', now(), now() - interval ''1 hour'')'), 'an event cannot end before it starts');
  perform t.assert(t.denied('insert into public.cal_events (subject_id, created_by, title, starts_at, ends_at) values (''' || s || ''', ''' || b || ''', ''Not mine'', now(), now())'), 'cannot create on behalf of another user');
  perform t.assert(t.denied('insert into public.cal_events (subject_id, created_by, title, starts_at, ends_at, source, source_ref) values (''' || s || ''', ''' || a || ''', ''Fake feed'', now(), now(), ''posts'', ''1'')'), 'users cannot write feed events');
  perform t.assert(t.denied('insert into public.cal_events (subject_id, created_by, person_id, title, starts_at, ends_at) values (''' || s2 || ''', ''' || a || ''', ''' || p || ''', ''Wrong subject'', now(), now())'), 'an event cannot name a person from another subject');
  update public.cal_events set status = 'done', title = 'Intro (done)' where id = e;
  perform t.assert((select status from public.cal_events where id = e) = 'done', 'users update their own events');

  perform t.as_service();
  id1 := public.cal_upsert_event(s, 'posts', 'post-1', 'post', 'Scheduled post', now(), now());
  id2 := public.cal_upsert_event(s, 'posts', 'post-1', 'post', 'Scheduled post (edited)', now(), now() + interval '30 minutes');
  perform t.assert(id1 = id2, 'the feed is idempotent on source and reference');
  perform t.assert((select title from public.cal_events where id = id1) = 'Scheduled post (edited)', 'the feed updates in place');

  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.cal_events') = 2, 'feed events show up for the owner');
  update public.cal_events set title = 'Hacked' where id = id1; get diagnostics n = row_count;
  perform t.assert(n = 0, 'users cannot edit feed events');
  delete from public.cal_events where id = id1; get diagnostics n = row_count;
  perform t.assert(n = 0, 'users cannot delete feed events');
  perform t.assert(t.denied('select public.cal_upsert_event(''' || s || ''', ''posts'', ''x'', ''post'', ''T'', now(), now())'), 'users cannot call the feed');
  perform t.assert(t.denied('select public.cal_remove_source(''' || s || ''', ''posts'')'), 'users cannot call the remove');

  delete from public.ppl_people where id = p;
  perform t.assert((select person_id from public.cal_events where id = e) is null, 'erasing a person keeps the event');

  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.cal_events') = 0, 'other users see nothing');
  perform t.assert(t.denied('insert into public.cal_events (subject_id, created_by, title, starts_at, ends_at) values (''' || s || ''', ''' || b || ''', ''Intruder'', now(), now())'), 'other users cannot write here');

  perform t.as_service();
  n := public.cal_remove_source(s, 'posts', 'post-1');
  perform t.assert(n = 1, 'the feed can withdraw an event');
  perform t.assert(public.cal_remove_source(s, 'posts') = 0, 'withdrawing nothing is fine');

  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.cal_events'), 'anon denied');
end $$;
rollback;
