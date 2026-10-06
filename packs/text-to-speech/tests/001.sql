-- Suite for text-to-speech 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; d uuid; d2 uuid; m uuid;
begin
  a := t.make_user('tts-a@example.test'); b := t.make_user('tts-b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  -- tts_clips
  perform t.as_user(a);
  perform t.assert(t.denied('select public.tts_record(''' || s || ''', ''' || a || ''', ''ext-1'', ''Welcome message'', ''Hello and welcome.'', ''tts-1'', ''alloy'', ''out/a/clip.mp3'')'), 'users cannot call tts_record');
  perform t.as_service();
  d := public.tts_record(s, a, 'ext-1', 'Welcome message', 'Hello and welcome.', 'tts-1', 'alloy', 'out/a/clip.mp3');
  perform t.assert(d = public.tts_record(s, a, 'ext-1', 'Welcome message', 'Hello and welcome.', 'tts-1', 'alloy', 'out/a/clip.mp3'), 'a replayed record returns the same item');
  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || d || ''' and kind = ''speech_clip''') = 1, 'record creates the base item');
  perform t.assert((select cost = 0 and charge_key is null from public.tts_clips where item_id = d), 'no charge by default');
  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || d || '''') = 0, 'no core credits touched');
  d2 := public.tts_record(s, a, 'ext-2', 'Welcome message', 'Hello and welcome.', 'tts-1', 'alloy', 'out/a/clip.mp3', 1);
  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''tts:' || d2 || ''' and amount > 0') = 1, 'a positive cost is charged in the same transaction');
  perform t.assert(t.denied('select public.tts_record(''' || s || ''', ''' || a || ''', ''ext-3'', ''Welcome message'', ''Hello and welcome.'', ''tts-1'', ''alloy'', ''out/a/clip.mp3'', 1000000000)'), 'an unaffordable cost is refused');
  perform t.assert(t.denied('select public.tts_record(''' || s || ''', ''' || b || ''', ''ext-4'', ''Welcome message'', ''Hello and welcome.'', ''tts-1'', ''alloy'', ''out/a/clip.mp3'')'), 'recording for a user without subject access is refused');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.tts_clips') = 0, 'other users see no records');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.tts_clips'), 'anon denied');
end $$;
rollback;
