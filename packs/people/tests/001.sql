begin;
do $$
declare n int; a uuid; m uuid; c uuid; x uuid; s uuid; p uuid; q uuid; tok uuid; r uuid;
begin
  a := t.make_user('owner@example.test'); m := t.make_user('staff@example.test');
  c := t.make_user('client@example.test'); x := t.make_user('stranger@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Studio') returning id into s;
  perform t.as_admin(); insert into public.subject_members (subject_id, user_id, role, accepted_at) values (s, m, 'member', now()); perform t.as_user(a);

  insert into public.ppl_people (subject_id, created_by, name, email, kind, assigned_to) values (s, a, 'Casey Client', 'client@example.test', 'client', m) returning id into p;
  insert into public.ppl_people (subject_id, created_by, name, kind) values (s, a, 'Pat Prospect', 'lead') returning id into q;
  perform t.assert(t.rows('select 1 from public.ppl_people') = 2, 'owner sees the roster');
  perform t.assert(t.denied('insert into public.ppl_people (subject_id, created_by, name, assigned_to) values (''' || s || ''', ''' || a || ''', ''N'', ''' || x || ''')'), 'cannot assign to someone outside the subject');
  perform t.assert(t.denied('update public.ppl_people set assigned_to = ''' || x || ''' where id = ''' || p || ''''), 'cannot reassign to someone outside the subject');
  perform t.assert(t.denied('insert into public.ppl_people (subject_id, created_by, name, email) values (''' || s || ''', ''' || a || ''', ''N'', ''Mixed@Case.com'')'), 'email must be normalised');
  perform t.assert(t.denied('insert into public.ppl_people (subject_id, created_by, name, user_id) values (''' || s || ''', ''' || a || ''', ''N'', ''' || c || ''')'), 'user_id cannot be written directly');
  perform t.assert(t.denied('update public.ppl_people set user_id = ''' || c || ''' where id = ''' || p || ''''), 'user_id cannot be updated directly');

  -- login invite
  perform t.assert(t.denied('select public.ppl_invite_login(''' || q || ''')'), 'a person without an email cannot be invited');
  tok := public.ppl_invite_login(p);
  perform t.assert(t.denied('select 1 from public.ppl_claims'), 'tokens are unreadable to users');

  perform t.as_user(x);
  perform t.assert(t.denied('select public.ppl_claim(''' || tok || ''')'), 'a different email cannot redeem the token');
  perform t.assert(t.denied('select public.ppl_invite_login(''' || p || ''')'), 'outsiders cannot invite');
  perform t.assert(t.rows('select 1 from public.ppl_people') = 0, 'outsiders see nobody');

  perform t.as_user(c);
  perform t.assert(t.rows('select 1 from public.ppl_people') = 0, 'before claiming, the client sees nothing');
  r := public.ppl_claim(tok);
  perform t.assert(r = p, 'claiming returns the person');
  perform t.assert(t.rows('select 1 from public.ppl_people') = 1, 'a client with a login sees only their own row');
  perform t.assert(public.ppl_is_self(p) and not public.ppl_is_self(q), 'ppl_is_self matches only their own row');
  update public.ppl_people set notes = 'x' where id = p; get diagnostics n = row_count;
  perform t.assert(n = 0, 'a client cannot edit the roster');
  delete from public.ppl_people where id = p; get diagnostics n = row_count;
  perform t.assert(n = 0, 'a client cannot delete');
  perform t.assert(t.denied('insert into public.ppl_people (subject_id, created_by, name) values (''' || s || ''', ''' || c || ''', ''Self'')'), 'a client cannot add people');
  perform t.assert(t.denied('select public.ppl_claim(''' || tok || ''')'), 'a token works once');

  perform t.as_user(m);
  perform t.assert(t.rows('select 1 from public.ppl_people') = 2, 'a staff member sees the roster');
  update public.ppl_people set notes = 'prefers mornings' where id = p;
  perform t.assert(t.denied('select public.ppl_invite_login(''' || p || ''')'), 'a person who already has a login cannot be invited again');

  perform t.as_user(a);
  perform public.ppl_unlink_login(p);
  perform t.as_user(c);
  perform t.assert(t.rows('select 1 from public.ppl_people') = 0, 'after unlinking the client sees nothing');
  perform t.as_user(x);
  perform t.assert(t.denied('select public.ppl_unlink_login(''' || p || ''')'), 'outsiders cannot unlink');

  perform t.as_user(a);
  insert into public.ppl_external_refs (subject_id, person_id, system, external_id) values (s, p, 'crm', 'c-100');
  perform t.assert(t.denied('insert into public.ppl_external_refs (subject_id, person_id, system, external_id) values (''' || s || ''', ''' || p || ''', ''crm'', ''c-101'')'), 'one reference per person and system');
  perform t.assert(t.denied('insert into public.ppl_external_refs (subject_id, person_id, system, external_id) values (''' || s || ''', ''' || q || ''', ''crm'', ''c-100'')'), 'one person per external id');
  perform t.assert(t.denied('insert into public.ppl_external_refs (subject_id, person_id, system, external_id) values (''' || s || ''', ''' || q || ''', ''Bad System'', ''z'')'), 'system is a lowercase token');
  perform t.as_user(c);
  perform t.assert(t.rows('select 1 from public.ppl_external_refs') = 0, 'a person never sees outside-system ids');
  perform t.as_user(x);
  perform t.assert(t.rows('select 1 from public.ppl_external_refs') = 0, 'outsiders see none');

  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.ppl_people'), 'anon denied');
  perform t.assert(t.denied('select public.ppl_claim(''' || tok || ''')'), 'anon cannot claim');
end $$;
rollback;
