begin;
create or replace function t.svc() returns void language plpgsql as $f$
begin
  perform t.as_admin();
  perform set_config('request.jwt.claim.sub', '', true);   -- a real service-role request carries no user sub
  perform t.as_service();
end $f$;
grant execute on function t.svc() to public;

do $$
declare a uuid; b uuid; s uuid; p uuid; c uuid; h uuid;
begin
  a := t.make_user('hist-owner@example.test'); b := t.make_user('hist-other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  insert into public.is_profiles (subject_id, kind, name) values (s, 'car', 'Cars') returning id into p;
  perform t.svc();
  insert into public.is_candidates (profile_id, subject_id, external_ref, title) values (p, s, 'x1', 'A car') returning id into c;
  perform public.is_record_price(c, 4817.69, 2200000, 'CRC', 'search');
  perform public.is_record_price(c, 4817.69, 2200000, 'CRC', 'check');   -- same price: no row
  perform public.is_record_price(c, 4000, 1826600, 'CRC', 'edit');
  perform public.is_record_price(gen_random_uuid(), 1, 1, 'USD', 'search');   -- unknown candidate: ignored
  perform t.assert((select count(*) from public.is_price_history) = 2, 'one row per change, none for an unchanged price or unknown candidate');
  perform t.assert((select price_native from public.is_price_history where candidate_id = c and source = 'search') = 2200000, 'the price as typed is kept');

  perform t.as_user(a);
  perform t.assert((select count(*) from public.is_price_history where candidate_id = c) = 2, 'the owner reads the history');
  perform t.assert(t.denied('insert into public.is_price_history (candidate_id, subject_id, price_usd, source) values (''' || c || ''', ''' || s || ''', 1, ''edit'')'), 'clients cannot write history');
  perform t.assert(t.denied('select public.is_record_price(''' || c || ''', 1, null, null, ''edit'')'), 'clients cannot call is_record_price');
  perform t.as_user(b);
  perform t.assert((select count(*) from public.is_price_history) = 0, 'another user sees nothing');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.is_price_history'), 'anon denied');

  perform t.svc();
  delete from public.is_candidates where id = c;
  perform t.assert((select count(*) from public.is_price_history) = 0, 'history goes with the candidate');
end $$;
rollback;
