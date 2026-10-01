-- Cross-pack: a team member sees a colleague's listings, applications and posts. Skips packs that are not installed.
begin;
do $$
declare a uuid; b uuid; s uuid; tok uuid; n int := 0;
begin
  if to_regclass('public.team_invites') is null then raise notice 'team not installed: skipped'; return; end if;
  a := t.make_user('owner@example.test'); b := t.make_user('colleague@example.test');
  perform t.as_user(a);
  insert into public.subjects (owner_id, kind, name) values (a, 'business', 'Shared') returning id into s;
  if to_regclass('public.rel_listings') is not null then insert into public.rel_listings (subject_id, created_by, title) values (s, a, 'shared listing'); end if;
  if to_regclass('public.sp_posts') is not null then insert into public.sp_posts (subject_id, created_by, body) values (s, a, 'shared post'); end if;
  if to_regclass('public.jb_applications') is not null then insert into public.jb_applications (subject_id, company, title) values (s, 'Acme', 'Role'); end if;
  tok := public.team_invite(s, 'colleague@example.test');
  perform t.as_user(b);
  if to_regclass('public.rel_listings') is not null then perform t.assert(t.rows('select 1 from public.rel_listings') = 0, 'pre-accept: no listings'); end if;
  perform public.team_accept(tok);
  if to_regclass('public.rel_listings') is not null then perform t.assert(t.rows('select 1 from public.rel_listings') = 1, 'member sees shared listings'); n := n + 1; end if;
  if to_regclass('public.sp_posts') is not null then perform t.assert(t.rows('select 1 from public.sp_posts') = 1, 'member sees shared posts'); n := n + 1; end if;
  if to_regclass('public.jb_applications') is not null then perform t.assert(t.rows('select 1 from public.jb_applications') = 1, 'member sees shared applications'); n := n + 1; end if;
  if to_regclass('public.rel_listings') is not null then
    perform t.assert(not t.denied('insert into public.rel_listings (subject_id, created_by, title) values (''' || s || ''', ''' || b || ''', ''member added'')'), 'member can add listings');
    perform t.assert(t.denied('delete from public.rel_listings') or t.rows('select 1 from public.rel_listings') = 2, 'member cannot delete owner listings');
  end if;
  perform t.as_user(a);
  perform public.team_remove_member(s, b);
  perform t.as_user(b);
  if to_regclass('public.rel_listings') is not null then perform t.assert(t.rows('select 1 from public.rel_listings') = 0, 'removal revokes access to every pack at once'); end if;
  raise notice 'integration: % shared-table checks', n;
end $$;
rollback;
