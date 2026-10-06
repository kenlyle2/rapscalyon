-- Suite for chat-with-file 0.1.0.
begin;
do $$
declare a uuid; b uuid; s uuid; c uuid;
begin
  a := t.make_user('cwf-a@example.test'); b := t.make_user('cwf-b@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;
  perform t.as_service();
  c := public.cht_start(s, a, 'multillm', 'gpt', 'Contract Q&A', 'conv-f1');
  perform t.assert(public.cwf_attach(c, 'uploads/a/contract.pdf', 'contract.pdf'), 'attach records the file once');
  perform t.assert(not public.cwf_attach(c, 'uploads/a/contract.pdf', 'contract.pdf'), 'a replayed attach is a no-op');
  perform t.assert(t.denied('select public.cwf_attach(''' || c || ''', ''uploads/a/other.pdf'', ''other.pdf'')'), 'a second file for the same chat is refused');
  perform t.assert(t.denied('select public.cwf_attach(''' || c || ''', ''../etc/passwd'', ''x'')'), 'a traversal key is refused');
  perform t.as_user(a);
  perform t.assert(t.rows('select 1 from public.cwf_sources where item_id = ''' || c || '''') = 1, 'the owner reads the source');
  perform t.assert(t.denied('insert into public.cwf_sources (item_id, subject_id, file_key, filename) values (''' || c || ''', ''' || s || ''', ''x.pdf'', ''x'')'), 'clients cannot insert sources');
  perform t.assert(t.denied('select public.cwf_attach(''' || c || ''', ''uploads/a/z.pdf'', ''z'')'), 'users cannot attach');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.cwf_sources') = 0, 'other users see nothing');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.cwf_sources'), 'anon denied');
end $$;
rollback;
