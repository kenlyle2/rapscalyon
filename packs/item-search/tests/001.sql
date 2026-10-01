begin;
create or replace function t.svc() returns void language plpgsql as $f$
begin
  perform t.as_admin();
  perform set_config('request.jwt.claim.sub', '', true);   -- a real service-role request carries no user sub
  perform t.as_service();
end $f$;
grant execute on function t.svc() to public;

do $$
declare a uuid; b uuid; s uuid; p uuid; c1 uuid; c2 uuid; it uuid; d uuid; n int; r record;
begin
  a := t.make_user('owner@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  insert into public.is_profiles (subject_id, kind, name, criteria) values (s, 'job', 'Search 1', '[{"titles":["Engineer"]}]') returning id into p;
  perform t.assert(t.denied('insert into public.is_profiles (subject_id, kind, name) values (''' || s || ''', ''Bad Kind'', ''x'')'), 'profile kind must be a slug');
  perform t.assert(t.denied('insert into public.is_profiles (subject_id, kind, name, criteria) values (''' || s || ''', ''job'', ''x'', ''{}'')'), 'criteria must be an array');
  perform t.assert(t.denied('update public.is_profiles set kind = ''other'' where id = ''' || p || ''''), 'profile kind is immutable for clients');
  perform t.assert(t.denied('insert into public.is_candidates (profile_id, subject_id, external_ref, title) values (''' || p || ''', ''' || s || ''', ''x'', ''y'')'), 'clients cannot write candidates');
  perform t.assert(t.denied('insert into public.is_outbox (subject_id, topic, ref_id) values (''' || s || ''', ''a.b'', gen_random_uuid())'), 'clients cannot touch the outbox');
  perform t.assert(t.denied('select count(*) from public.is_outbox'), 'clients cannot read the outbox');

  -- plan cap on profiles
  perform t.as_admin();
  insert into public.admin_settings (setting_key, setting_value) select 'plan_limits', '{}'::jsonb where not exists (select 1 from public.admin_settings where setting_key = 'plan_limits');
  update public.admin_settings set setting_value = jsonb_set(setting_value, '{free}', coalesce(setting_value -> 'free', '{}'::jsonb) || '{"is_max_profiles":2}') where setting_key = 'plan_limits';
  perform t.as_user(a);
  insert into public.is_profiles (subject_id, kind, name) values (s, 'job', 'Search 2');
  perform t.assert(t.denied('insert into public.is_profiles (subject_id, kind, name) values (''' || s || ''', ''job'', ''Search 3'')'), 'profile cap enforced for users');

  -- the matcher (service role) proposes candidates; re-delivery is idempotent
  perform t.svc();
  insert into public.is_candidates (profile_id, subject_id, external_ref, title, url, reason) values (p, s, 'ext-1', 'Candidate One', 'https://x.test/1', '{"score":0.9}') returning id into c1;
  insert into public.is_candidates (profile_id, subject_id, external_ref, title) values (p, s, 'ext-2', 'Candidate Two') returning id into c2;
  perform t.assert(t.denied('insert into public.is_candidates (profile_id, subject_id, external_ref, title) values (''' || p || ''', ''' || s || ''', ''ext-1'', ''dup'')'), 'duplicate external_ref refused');
  perform t.assert(t.denied('insert into public.is_candidates (profile_id, subject_id, external_ref, title) values (''' || p || ''', gen_random_uuid(), ''ext-9'', ''wrong subject'')'), 'candidate must match its profile subject');

  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.is_candidates') = 2, 'owner sees candidates');
  it := public.is_accept_candidate(c1);
  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || it || ''' and kind = ''job'' and title = ''Candidate One''') = 1, 'accept creates an item of the profile kind');
  perform t.assert(public.is_accept_candidate(c1) = it, 'accept is idempotent');
  perform t.assert(t.rows('select 1 from public.is_candidates where id = ''' || c1 || ''' and status = ''accepted'' and item_id = ''' || it || '''') = 1, 'candidate linked to its item');
  perform public.is_dismiss_candidate(c2);
  perform t.assert(t.rows('select 1 from public.is_candidates where id = ''' || c2 || ''' and status = ''dismissed''') = 1, 'dismiss works');
  perform t.assert(t.denied('update public.is_candidates set status = ''accepted'' where id = ''' || c2 || ''''), 'clients cannot update candidates directly');

  -- other users: nothing visible, nothing callable
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.is_profiles') = 0 and t.rows('select 1 from public.is_candidates') = 0, 'other users see nothing');
  perform t.assert(t.denied('select public.is_accept_candidate(''' || c2 || ''')'), 'cannot accept a foreign candidate');
  perform t.assert(t.denied('select public.is_dismiss_candidate(''' || c2 || ''')'), 'cannot dismiss a foreign candidate');

  -- dispatch: service creates, user reviews, worker claims exactly once
  perform t.svc();
  insert into public.is_dispatches (item_id, subject_id, payload) values (it, s, '{"answers":{"q1":"a"}}') returning id into d;
  perform t.assert((select count(*) from public.is_claim_next_dispatch()) = 0, 'nothing claimable before approval');
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.is_dispatches') = 1, 'owner sees the dispatch');
  perform t.assert(t.denied('update public.is_dispatches set status = ''approved'' where id = ''' || d || ''''), 'clients cannot approve by updating the table');
  perform public.is_set_dispatch_overrides(d, '{"q1":"edited"}');
  perform t.assert(t.denied('select public.is_set_dispatch_overrides(''' || d || ''', ''[1]'')'), 'overrides must be an object');
  perform t.as_user(b);
  perform t.assert(t.denied('select public.is_approve_dispatch(''' || d || ''')'), 'cannot approve a foreign dispatch');
  perform t.as_user(a);
  perform t.assert(t.denied('select public.is_approve_dispatch(''' || d || ''', -1)'), 'delay must be non-negative');
  perform public.is_approve_dispatch(d, 3600);
  perform t.assert(t.denied('select public.is_set_dispatch_overrides(''' || d || ''', ''{}'')'), 'overrides locked after approval');
  perform t.assert(t.denied('select public.is_claim_next_dispatch()'), 'users cannot claim dispatches');
  perform t.assert(t.denied('select public.is_complete_dispatch(''' || d || ''', true)'), 'users cannot complete dispatches');
  perform t.svc();
  perform t.assert((select count(*) from public.is_claim_next_dispatch()) = 0, 'delayed dispatch is not released early');
  update public.is_dispatches set release_at = now() - interval '1 second' where id = d;
  select * into r from public.is_claim_next_dispatch();
  perform t.assert(r.id = d and r.status = 'claimed' and r.attempts = 1 and r.overrides = '{"q1":"edited"}'::jsonb, 'worker claims the approved dispatch with overrides');
  perform t.assert((select count(*) from public.is_claim_next_dispatch()) = 0, 'a claimed dispatch is not claimed twice');
  update public.is_dispatches set claimed_at = now() - interval '11 minutes' where id = d;
  select * into r from public.is_claim_next_dispatch();
  perform t.assert(r.id = d and r.attempts = 2, 'stale claims are retried');
  perform public.is_complete_dispatch(d, false, 'ats rejected the form');
  perform t.assert(t.rows('select 1 from public.is_dispatches where id = ''' || d || ''' and status = ''failed'' and error = ''ats rejected the form''') = 1, 'failure recorded');
  perform t.assert(t.denied('select public.is_complete_dispatch(''' || d || ''', true)'), 'only claimed dispatches can complete');
  insert into public.is_dispatches (item_id, subject_id, status, attempts, claimed_at) values (it, s, 'claimed', 5, now() - interval '11 minutes') returning id into d;
  perform t.assert((select count(*) from public.is_claim_next_dispatch()) = 0, 'abandoned dispatch is not retried');
  perform t.assert(t.rows('select 1 from public.is_dispatches where id = ''' || d || ''' and status = ''failed''') = 1, 'abandoned after 5 attempts');

  -- cancel, and the outbox
  insert into public.is_dispatches (item_id, subject_id) values (it, s) returning id into d;
  perform t.as_user(a);
  perform public.is_cancel_dispatch(d);
  perform t.assert(t.denied('select public.is_approve_dispatch(''' || d || ''')'), 'cancelled dispatch cannot be approved');
  perform t.svc();
  select count(*) into n from public.is_claim_outbox(100) where topic in ('profile.changed', 'candidate.accepted', 'dispatch.approved');
  perform t.assert(n = 4, 'outbox carries exactly 2 profile.changed, 1 candidate.accepted and 1 dispatch.approved');
  perform t.assert((select count(*) from public.is_claim_outbox(100)) = 0, 'outbox rows are claimed once');

  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.is_profiles'), 'anon denied');
  perform t.assert(t.denied('select public.is_accept_candidate(gen_random_uuid())'), 'anon cannot call is_accept_candidate');
end $$;
rollback;
