begin;
create or replace function t.svc() returns void language plpgsql as $f$
begin
  perform t.as_admin();
  perform set_config('request.jwt.claim.sub', '', true);   -- a real service-role request carries no user sub
  perform t.as_service();
end $f$;
grant execute on function t.svc() to public;

do $$
declare a uuid; b uuid; s uuid; s2 uuid; p uuid; p2 uuid; c uuid; c2 uuid; l uuid; l2 uuid;
begin
  a := t.make_user('list-owner@example.test'); b := t.make_user('list-other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  insert into public.is_profiles (subject_id, kind, name) values (s, 'car', 'Cars') returning id into p;
  perform t.as_user(b);
  insert into public.subjects (owner_id, kind, name) values (b, 'individual', 'Them') returning id into s2;
  insert into public.is_profiles (subject_id, kind, name) values (s2, 'car', 'Cars') returning id into p2;
  perform t.svc();
  insert into public.is_candidates (profile_id, subject_id, external_ref, title) values (p, s, 'l1', 'A car') returning id into c;
  insert into public.is_candidates (profile_id, subject_id, external_ref, title) values (p2, s2, 'l2', 'Their car') returning id into c2;

  perform t.as_user(a);
  l := public.is_create_list(s, '  4x4s ');
  perform t.assert(public.is_create_list(s, '4X4S') = l, 'the same name (any case) is the same list');
  l2 := public.is_create_list(s, 'For Mom');
  perform public.is_add_to_list(l, c); perform public.is_add_to_list(l, c); perform public.is_add_to_list(l2, c);
  perform t.assert((select count(*) from public.is_list_items where candidate_id = c) = 2, 'a car can be on two lists, once each');
  perform t.assert((select name from public.is_lists where id = l) = '4x4s', 'name is trimmed');
  perform t.assert(t.denied('select public.is_add_to_list(''' || l || ''', ''' || c2 || ''')'), 'cannot list another subject''s car');
  perform t.assert(t.denied('select public.is_create_list(''' || s2 || ''', ''x'')'), 'cannot create a list in another subject');
  perform t.assert(t.denied('insert into public.is_lists (subject_id, name) values (''' || s || ''', ''direct'')'), 'clients cannot write lists directly');
  perform t.assert(t.denied('select public.is_create_list(''' || s || ''', ''   '')'), 'empty names are refused');
  perform public.is_rename_list(l2, 'Mom');
  perform public.is_remove_from_list(l2, c);
  perform t.assert((select count(*) from public.is_list_items where list_id = l2) = 0, 'removed from the list');

  perform t.as_user(b);
  perform t.assert((select count(*) from public.is_lists) = 0, 'another user sees no lists');
  perform t.assert(t.denied('select public.is_delete_list(''' || l || ''')'), 'another user cannot delete the list');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.is_lists'), 'anon denied');

  perform t.as_user(a);
  perform public.is_delete_list(l);
  perform t.svc();
  perform t.assert((select count(*) from public.is_candidates where id = c) = 1, 'deleting a list keeps the candidate');
  perform t.assert((select count(*) from public.is_list_items where candidate_id = c) = 0, 'and clears its memberships');
end $$;
rollback;
