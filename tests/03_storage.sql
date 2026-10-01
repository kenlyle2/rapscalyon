begin;
do $$
declare a uuid; b uuid; s uuid; tok uuid;
begin
  if to_regclass('storage.objects') is null then raise notice 'no storage schema: skipped'; return; end if;
  a := t.make_user('files-owner@example.test'); b := t.make_user('files-other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Files Co') returning id into s;
  insert into storage.objects (bucket_id, name, owner_id) values ('media', s || '/logo.png', a::text);
  perform t.assert(t.rows('select 1 from storage.objects where bucket_id = ''media''') = 1, 'owner sees own subject files');
  perform t.assert(t.denied('insert into storage.objects (bucket_id, name, owner_id) values (''media'', ''not-a-uuid/x.png'', ''' || a || ''')'), 'paths must start with a subject id');
  perform t.assert(t.denied('insert into storage.objects (bucket_id, name, owner_id) values (''media'', ''' || gen_random_uuid() || '/x.png'', ''' || a || ''')'), 'cannot write into a subject you do not have');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from storage.objects where bucket_id = ''media''') = 0, 'other users see nothing');
  perform t.assert(t.denied('insert into storage.objects (bucket_id, name, owner_id) values (''media'', ''' || s || '/evil.png'', ''' || b || ''')'), 'other users cannot write into the subject');
  perform t.as_anon();
  perform t.assert(t.rows('select 1 from storage.objects where bucket_id = ''media''') = 0, 'anon sees nothing');
  perform t.as_admin();
  perform t.assert((select not public from storage.buckets where id = 'media'), 'bucket is private');
end $$;
rollback;
