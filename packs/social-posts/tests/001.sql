begin;
do $$
declare a uuid; b uuid; s uuid; p uuid; p2 uuid; n int;
begin
  a := t.make_user('poster@example.test'); b := t.make_user('other@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Cafe') returning id into s;
  insert into public.sp_posts (subject_id, created_by, body) values (s, a, 'draft one') returning id into p;
  perform t.assert(t.denied('insert into public.sp_posts (subject_id, created_by, body, status) values (''' || s || ''', ''' || a || ''', ''x'', ''published'')'), 'users cannot create published posts');
  perform t.assert(t.denied('insert into public.sp_posts (subject_id, created_by, body, status) values (''' || s || ''', ''' || a || ''', ''x'', ''scheduled'')'), 'scheduled requires scheduled_for');
  perform t.assert(t.denied('update public.sp_posts set status = ''published'' where id = ''' || p || ''''), 'users cannot mark posts published');
  insert into public.sp_posts (subject_id, created_by, body, status, scheduled_for) values (s, a, 'due now', 'scheduled', now() - interval '1 minute') returning id into p2;
  insert into public.sp_posts (subject_id, created_by, body, status, scheduled_for) values (s, a, 'later', 'scheduled', now() + interval '1 day');
  perform t.assert(t.denied('select * from public.sp_claim_due_posts()'), 'users cannot claim posts');
  perform t.as_user(b);
  perform t.assert(t.rows('select 1 from public.sp_posts') = 0, 'other users see nothing');
  perform t.as_anon();
  perform t.assert(t.denied('select 1 from public.sp_posts'), 'anon denied');
  perform t.as_service();
  select count(*) into n from public.sp_claim_due_posts();
  perform t.assert(n = 1, 'publisher claims exactly the due post');
  select count(*) into n from public.sp_claim_due_posts();
  perform t.assert(n = 0, 'a claimed post is not claimed twice');
  update public.sp_posts set status = 'failed', error = 'rate limited' where id = p2;
  perform t.as_user(a);
  perform t.assert(not t.denied('update public.sp_posts set status = ''draft'' where id = ''' || p2 || ''''), 'user can retry a failed post by moving it back to draft');
end $$;
rollback;
