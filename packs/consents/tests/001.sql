begin;
do $$
declare a uuid; b uuid; s uuid; s2 uuid; pid uuid; n int; ok boolean;
begin
  a := t.make_user('owner@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Studio') returning id into s;
  perform t.assert(not public.cn_has_consent(s, 'sms_messages', '+50688880000'), 'no row means no consent');
  insert into public.cn_consents (subject_id, created_by, purpose, person_key, action, source, wording_version, evidence, occurred_at)
    values (s, a, 'sms_messages', '+50688880000', 'granted', 'web_form', 'v1', 'ticked the box on the intake form', now() - interval '10 seconds');
  perform t.assert(public.cn_has_consent(s, 'sms_messages', '  +50688880000 '), 'a grant counts, and the key is normalised');
  perform t.assert(not public.cn_has_consent(s, 'session_recording', '+50688880000'), 'consent is per purpose');
  perform t.assert(not public.cn_has_consent(s, 'sms_messages', '+50699990000'), 'consent is per person');

  perform t.assert(t.denied('update public.cn_consents set action = ''withdrawn'''), 'the ledger cannot be edited');
  perform t.assert(t.denied('delete from public.cn_consents'), 'the ledger cannot be deleted from');
  perform t.assert(t.denied('insert into public.cn_consents (subject_id, created_by, purpose, person_key, action, source) values (''' || s || ''', ''' || a || ''', ''Bad Purpose'', ''+50688880000'', ''granted'', ''web_form'')'), 'purpose must be a lowercase token');
  perform t.assert(t.denied('insert into public.cn_consents (subject_id, created_by, purpose, person_key, action, source) values (''' || s || ''', ''' || a || ''', ''sms_messages'', ''  Mixed@Case.com '', ''granted'', ''web_form'')'), 'the key must already be normalised');
  perform t.assert(t.denied('insert into public.cn_consents (subject_id, created_by, purpose, person_key, action, source) values (''' || s || ''', ''' || b || ''', ''sms_messages'', ''+50688880000'', ''granted'', ''web_form'')'), 'cannot record on behalf of another user');

  -- a user records a withdrawal as a new row; the latest row wins
  insert into public.cn_consents (subject_id, created_by, purpose, person_key, action, source, occurred_at)
    values (s, a, 'sms_messages', '+50688880000', 'withdrawn', 'verbal', now() - interval '5 seconds');
  perform t.assert(not public.cn_has_consent(s, 'sms_messages', '+50688880000'), 'a later withdrawal wins');
  insert into public.cn_consents (subject_id, created_by, purpose, person_key, action, source, occurred_at)
    values (s, a, 'sms_messages', '+50688880000', 'granted', 'written', now() - interval '2 seconds');
  perform t.assert(public.cn_has_consent(s, 'sms_messages', '+50688880000'), 'a later grant wins again');

  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.cn_consents') = 0, 'other users see nothing');
  perform t.assert(not public.cn_has_consent(s, 'sms_messages', '+50688880000'), 'other users get no answer about a subject they cannot access');
  perform t.assert(t.denied('insert into public.cn_consents (subject_id, created_by, purpose, person_key, action, source) values (''' || s || ''', ''' || b || ''', ''sms_messages'', ''+50688880000'', ''withdrawn'', ''web_form'')'), 'other users cannot write into this subject');

  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.cn_consents'), 'anon denied');
  perform t.assert(t.denied('select public.cn_has_consent(''' || s || ''', ''sms_messages'', ''+50688880000'')'), 'anon cannot call the check');

  perform t.as_user(a);
  perform t.assert(t.denied('select public.cn_withdraw(''' || s || ''', ''sms_messages'', ''+50688880000'')'), 'users cannot call the service-only withdraw');

  -- a consent can name the person it is about, but only a person of the same subject
  insert into public.ppl_people (subject_id, created_by, name, phone) values (s, a, 'Casey', '+50688880000') returning id into pid;
  insert into public.cn_consents (subject_id, created_by, person_id, purpose, person_key, action, source) values (s, a, pid, 'session_recording', '+50688880000', 'granted', 'written');
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Other studio') returning id into s2;
  perform t.assert(t.denied('insert into public.cn_consents (subject_id, created_by, person_id, purpose, person_key, action, source) values (''' || s2 || ''', ''' || a || ''', ''' || pid || ''', ''session_recording'', ''+50688880000'', ''granted'', ''written'')'), 'a consent cannot name a person from another subject');
  delete from public.ppl_people where id = pid;
  perform t.assert((select person_id from public.cn_consents where purpose = 'session_recording') is null, 'erasing a person keeps the ledger row');

  perform t.as_service();
  select public.cn_withdraw(s, 'sms_messages', ' +50688880000', 'sms_reply', 'STOP') into ok;
  perform t.assert(ok, 'an inbound STOP records a withdrawal');
  select public.cn_withdraw(s, 'sms_messages', '+50688880000') into ok;
  perform t.assert(not ok, 'a second STOP records nothing');
  select public.cn_withdraw(s, 'sms_messages', '+50611110000') into ok;
  perform t.assert(not ok, 'a STOP from someone who never consented records nothing');
  perform t.as_admin();
  select count(*) into n from public.cn_consents where evidence = 'STOP';
  perform t.assert(n = 1, 'exactly one STOP row exists');
end $$;
rollback;
