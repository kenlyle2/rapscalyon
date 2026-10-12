begin;
do $$
declare a uuid; b uuid; s uuid; p uuid; n bigint;
begin
  a := t.make_user('owner@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Studio') returning id into s;
  insert into public.ppl_people (subject_id, created_by, name) values (s, a, 'Casey') returning id into p;
  insert into public.cal_events (subject_id, created_by, person_id, title, kind, status, starts_at, ends_at) values
    (s, a, p, 'a', 'meal',    'missed',    now() - interval '3 days', now() - interval '3 days'),
    (s, a, p, 'b', 'meal',    'scheduled', now() - interval '2 days', now() - interval '2 days'),
    (s, a, p, 'c', 'meal',    'done',      now() - interval '1 day',  now() - interval '1 day'),
    (s, a, p, 'd', 'workout', 'cancelled', now() - interval '1 day',  now() - interval '1 day'),
    (s, a, null, 'e', 'workout', 'missed', now() - interval '20 days', now() - interval '20 days'),
    (s, a, p, 'f', 'meal',    'scheduled', now() + interval '1 day',  now() + interval '1 day');
  select missed into n from public.cal_missed_counts(s, now() - interval '7 days', now() + interval '7 days') where kind = 'meal';
  perform t.assert(n = 2, 'marked-missed and past-still-scheduled count; done and future do not');
  perform t.assert(not exists (select 1 from public.cal_missed_counts(s, now() - interval '7 days', now() + interval '7 days') where kind = 'workout'), 'cancelled is not missed and the window excludes older events');
  select sum(missed) into n from public.cal_missed_counts(s, now() - interval '30 days', now() + interval '7 days');
  perform t.assert(n = 3, 'a wider window includes the older miss');
  select sum(missed) into n from public.cal_missed_counts(s, now() - interval '30 days', now() + interval '7 days', p);
  perform t.assert(n = 2, 'filter by person');
  update public.cal_events set status = 'missed' where title = 'f';
  perform t.as_user(b);
  perform t.assert(not exists (select 1 from public.cal_missed_counts(s, now() - interval '30 days', now() + interval '7 days')), 'other users get no counts');
  perform t.as_anon();
  perform t.assert(t.denied('select * from public.cal_missed_counts(''' || s || ''', now(), now())'), 'anon denied');
end $$;
rollback;
