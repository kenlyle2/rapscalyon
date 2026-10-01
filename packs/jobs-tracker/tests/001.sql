begin;
do $$
declare a uuid; b uuid; s uuid; j uuid;
begin
  a := t.make_user('seeker@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  insert into public.jb_applications (subject_id, company, title, url) values (s, 'Acme', 'Engineer', 'https://acme.test/job') returning id into j;
  perform t.assert(t.denied('insert into public.jb_applications (subject_id, company, title, url) values (''' || s || ''', ''X'', ''Y'', ''javascript:alert(1)'')'), 'only http(s) urls');
  perform t.assert(t.denied('insert into public.jb_applications (subject_id, company, title, salary_min, salary_max) values (''' || s || ''', ''X'', ''Y'', 200, 100)'), 'salary range must be ordered');
  update public.jb_applications set status = 'applied' where id = j;
  perform t.assert((select applied_at = current_date from public.jb_applications where id = j), 'applied_at defaulted on first apply');
  perform t.assert(t.rows('select 1 from public.jb_application_events where application_id = ''' || j || ''' and kind = ''status_change''') = 1, 'status change logged by trigger');
  perform t.assert(t.denied('insert into public.jb_application_events (application_id, subject_id, kind) values (''' || j || ''', ''' || s || ''', ''status_change'')'), 'clients cannot forge status_change events');
  insert into public.jb_application_events (application_id, subject_id, kind, note) values (j, s, 'note', 'recruiter called');
  perform t.assert(t.denied('update public.jb_application_events set note = ''edited'''), 'events are append-only for clients');
  perform t.assert(t.denied('delete from public.jb_application_events'), 'events cannot be deleted by clients');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.jb_applications') = 0 and t.rows('select 1 from public.jb_application_events') = 0, 'other users see nothing');
  perform t.assert(t.denied('insert into public.jb_application_events (application_id, subject_id, kind) values (''' || j || ''', ''' || s || ''', ''note'')'), 'cannot log events on foreign applications');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.jb_applications'), 'anon denied');
end $$;
rollback;
