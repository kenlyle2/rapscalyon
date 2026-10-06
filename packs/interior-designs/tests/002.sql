-- Suite for interior-designs 0.2.0: ingest helpers.
begin;
do $$
declare a uuid; b uuid; c uuid; u uuid; s1 uuid; s2 uuid; s3 uuid; n bigint;
begin
  a := t.make_user('Homeowner@Example.test', false, 'pro'); b := t.make_user('stranger@example.test', false, 'pro');
  perform t.as_admin();
  insert into public.admin_settings (setting_key, setting_value) values ('plan_limits', '{"pro": {"ind_max_subjects": 5}}')
    on conflict (setting_key) do update set setting_value = public.admin_settings.setting_value || '{"pro": {"ind_max_subjects": 5}}'::jsonb;
  perform t.as_admin();
  update auth.users set email_confirmed_at = now() where id in (a, b);
  perform t.as_user(a);
  perform t.assert(t.denied('select public.idg_resolve_user(''homeowner@example.test'')'), 'users cannot resolve emails');
  perform t.assert(t.denied('select public.idg_ensure_subject(''' || a || ''', null)'), 'users cannot create spaces through the ingest helper');
  perform t.as_service();
  perform t.assert(public.idg_resolve_user('  homeowner@example.TEST ') = a, 'email resolves case-insensitively, trimmed');
  perform t.assert(public.idg_resolve_user('nobody@example.test') is null, 'unknown email resolves to nothing');
  perform t.assert(public.idg_resolve_user('') is null and public.idg_resolve_user(null) is null, 'empty email resolves to nothing');
  -- unconfirmed accounts never resolve
  perform t.as_admin(); update auth.users set email_confirmed_at = null where id = b; perform t.as_service();
  perform t.assert(public.idg_resolve_user('stranger@example.test') is null, 'unconfirmed email does not resolve');
  perform t.as_admin(); update auth.users set email_confirmed_at = now() where id = b; perform t.as_service();
  perform t.assert(public.idg_resolve_user('stranger@example.test') = b, 'confirmed email resolves');
  -- default space: created once, reused
  s1 := public.idg_ensure_subject(a, null);
  perform t.assert((select owner_id = a and kind = 'individual' and name = 'My designs' from public.subjects where id = s1), 'first use creates the default space');
  perform t.assert(public.idg_ensure_subject(a, null) = s1 and public.idg_ensure_subject(a, '   ') = s1, 'default space is reused, blank name means default');
  -- named spaces: found case-insensitively, created when new
  s2 := public.idg_ensure_subject(a, 'Beach house');
  perform t.as_admin(); update public.subjects set created_at = created_at + interval '1 second' where id = s2; perform t.as_service(); -- one transaction shares now(); real calls do not
  perform t.assert(s2 <> s1 and public.idg_ensure_subject(a, 'beach HOUSE') = s2, 'a named space is created once and found regardless of case');
  perform t.assert(public.idg_ensure_subject(a, null) = s1, 'the default stays the oldest space');
  perform t.assert(t.rows('select 1 from public.subjects where owner_id = ''' || a || '''') = 2, 'no duplicates created');
  -- never another user's space, never a membership
  s3 := public.idg_ensure_subject(b, 'Beach house');
  perform t.assert(s3 <> s2, 'the same name for another user is a different space');
  perform t.as_admin(); insert into public.subject_members (subject_id, user_id, role, accepted_at) values (s2, b, 'member', now()); perform t.as_service();
  perform t.assert(public.idg_ensure_subject(b, null) = s3, 'a membership in someone else''s space is never the default');
  perform t.assert((select owner_id = b from public.subjects where id = public.idg_ensure_subject(b, 'Beach house')), 'a named lookup only finds owned spaces');
  -- plan limits still apply when subject-individual is installed (free tier: one individual space)
  if exists (select 1 from pg_trigger where tgname = 'ind_subjects_limit') then
    perform t.as_admin(); c := t.make_user('free@example.test'); update auth.users set email_confirmed_at = now() where id = c; perform t.as_service();
    perform public.idg_ensure_subject(c, null);
    perform t.assert(t.denied('select public.idg_ensure_subject(''' || c || ''', ''Second home'')'), 'the plan limit on spaces is honoured');
  end if;
  -- bad input
  begin perform public.idg_ensure_subject(gen_random_uuid(), null); perform t.assert(false, 'unknown user refused');
  exception when sqlstate '22023' then null; end;
  begin perform public.idg_ensure_subject(a, repeat('x', 201)); perform t.assert(false, 'over-long name refused');
  exception when sqlstate '22023' then null; end;
  -- end to end with the recorder: resolve, ensure, record
  u := public.idg_resolve_user('homeowner@example.test');
  perform public.idg_record_design(public.idg_ensure_subject(u, null), u, 'resp-1', 'airy', 'living room', 'scandi', null, array['designs/x/1.png']);
  perform t.assert(t.rows('select 1 from public.idg_designs where requested_by = ''' || a || ''' and prediction_id = ''resp-1''') = 1, 'recorded under the resolved user and space');
end $$;
rollback;
