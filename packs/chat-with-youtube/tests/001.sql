-- Suite for chat-with-youtube 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; c uuid;
begin
  a := t.make_user('cwy-a@example.test'); b := t.make_user('cwy-b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  perform t.as_service();
  c := public.cht_start(s, a, 'gemini', 'flash', 'Talk notes', 'conv-y1');
  perform t.assert(public.cwy_attach(c, 'https://www.youtube.com/watch?v=abc', 'A talk', 'casual', 'friendly', 'hello there', 'a greeting'), 'attach records the video once');
  perform t.assert(not public.cwy_attach(c, 'https://www.youtube.com/watch?v=abc', 'A talk', 'casual', 'friendly', 'hello there', 'a greeting'), 'a replayed attach is a no-op');
  perform t.assert(t.denied('select public.cwy_attach(''' || c || ''', ''https://www.youtube.com/watch?v=zzz'', ''Other'', null, null, ''x'', null)'), 'a second video for the same chat is refused');
  perform t.assert(public.cwy_mark_ingested(c), 'ingestion is marked once');
  perform t.assert(not public.cwy_mark_ingested(c), 'a replayed mark is a no-op');
  perform t.assert((select ingestion_done from public.cwy_sources where item_id = c), 'flag stored');
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.cwy_sources where item_id = ''' || c || '''') = 1, 'the owner reads the source');
  perform t.assert(t.denied('update public.cwy_sources set ingestion_done = false where item_id = ''' || c || ''''), 'clients cannot update sources');
  perform t.assert(t.denied('select public.cwy_mark_ingested(''' || c || ''')'), 'users cannot mark ingestion');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.cwy_sources') = 0, 'other users see nothing');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.cwy_sources'), 'anon denied');
end $$;
rollback;
