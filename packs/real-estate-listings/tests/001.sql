begin;
do $$
declare a uuid; b uuid; s uuid; l uuid; l2 uuid; i int;
begin
  a := t.make_user('agent@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Agency') returning id into s;
  insert into public.rel_listings (subject_id, created_by, title, price_minor, currency, bedrooms) values (s, a, '2BR flat', 250000000, 'USD', 2) returning id into l;
  perform t.assert(t.denied('insert into public.rel_listings (subject_id, created_by, title) values (''' || s || ''', ''' || b || ''', ''spoofed author'')'), 'created_by must be the caller');
  perform t.assert(t.denied('insert into public.rel_listings (subject_id, created_by, title, price_minor) values (''' || s || ''', ''' || a || ''', ''neg'', -1)'), 'negative price rejected');
  perform t.assert(t.denied('update public.rel_listings set listed_at = now() where id = ''' || l || ''''), 'listed_at is not user-writable');
  update public.rel_listings set status = 'active' where id = l;
  perform t.assert((select listed_at is not null from public.rel_listings where id = l), 'listed_at set on first activation');
  insert into public.rel_listing_photos (listing_id, subject_id, storage_path, position) values (l, s, 'u/1.jpg', 0);
  perform t.assert(t.denied('insert into public.rel_listing_photos (listing_id, subject_id, storage_path, position) values (''' || l || ''', gen_random_uuid(), ''u/2.jpg'', 1)'), 'photo cannot claim a different subject than its listing');

  for i in 1..9 loop
    insert into public.rel_listings (subject_id, created_by, title, status) values (s, a, 'L' || i, 'active');
  end loop;
  perform t.assert(t.denied('insert into public.rel_listings (subject_id, created_by, title, status) values (''' || s || ''', ''' || a || ''', ''eleventh'', ''active'')'), 'rel_max_active_listings (10) enforced');
  perform t.assert(not t.denied('insert into public.rel_listings (subject_id, created_by, title, status) values (''' || s || ''', ''' || a || ''', ''draft ok'', ''draft'')'), 'drafts do not count');

  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.rel_listings') = 0, 'other users see no listings');
  perform t.assert(t.rows('select 1 from public.rel_listing_photos') = 0, 'other users see no photos');
  perform t.assert(t.denied('insert into public.rel_listings (subject_id, created_by, title) values (''' || s || ''', ''' || b || ''', ''intruder'')'), 'cannot add listings to a foreign subject');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.rel_listings'), 'anon denied');
  perform t.as_service();
  perform t.assert((select credit_cost from public.operation_pricing where operation = 'rel.generate_description') = 0, 'operations registered at price 0');
end $$;
rollback;
