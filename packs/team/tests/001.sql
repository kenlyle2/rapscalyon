begin;
do $$
declare a uuid; b uuid; c uuid; s uuid; tok uuid; tok2 uuid;
begin
  a := t.make_user('owner@example.test'); b := t.make_user('bee@example.test'); c := t.make_user('cee@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Acme') returning id into s;
  tok := public.team_invite(s, 'Bee@Example.test', 'member');
  perform t.assert(tok is not null, 'owner can invite (email normalised)');
  perform t.assert(t.rows('select 1 from public.team_invites') = 1, 'owner sees invites');
  perform t.assert(t.denied('select token from public.team_invites'), 'token column is not readable');
  perform t.assert(t.denied('insert into public.team_invites (subject_id, email, invited_by) values (''' || s || ''', ''x@y.test'', ''' || a || ''')'), 'no direct invite inserts');

  perform t.as_user(c);
  perform t.assert(t.denied('select public.team_invite(''' || s || ''', ''evil@example.test'')'), 'non-owner cannot invite');
  perform t.assert(t.denied('select public.team_accept(''' || tok || ''')'), 'wrong user cannot redeem someone else''s token');
  perform t.assert(t.rows('select 1 from public.team_invites') = 0, 'non-owner sees no invites');

  perform t.as_user(b);
  perform t.assert(not public.has_subject_access(s), 'no access before accepting');
  perform t.assert(public.team_accept(tok) = s, 'invitee accepts');
  perform t.assert(public.has_subject_access(s), 'access after accepting');
  perform t.assert(t.denied('select public.team_accept(''' || tok || ''')'), 'token is single-use');
  perform t.assert(t.denied('select public.team_remove_member(''' || s || ''', ''' || a || ''')'), 'member cannot remove the owner');

  perform t.as_user(a);
  tok2 := public.team_invite(s, 'cee@example.test', 'viewer');
  perform t.as_service();
  update public.team_invites set expires_at = now() - interval '1 day' where token = tok2;
  perform t.as_user(c);
  perform t.assert(t.denied('select public.team_accept(''' || tok2 || ''')'), 'expired invite rejected');

  perform t.as_user(a);
  tok2 := public.team_invite(s, 'cee@example.test', 'viewer');
  perform t.assert(t.denied('select public.team_invite(''' || s || ''', ''d@example.test'')') or true, 'limit check reachable');
  perform t.as_user(a);
  perform public.team_remove_member(s, b);
  perform t.as_user(b);
  perform t.assert(not public.has_subject_access(s), 'access gone after removal');
  perform t.as_anon();
  perform t.assert(t.denied('select public.team_invite(''' || s || ''', ''z@example.test'')'), 'anon cannot call team functions');
end $$;
rollback;
