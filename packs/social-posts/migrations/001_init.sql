create table public.sp_posts (
  id            uuid primary key default gen_random_uuid(),
  subject_id    uuid not null references public.subjects(id) on delete cascade,
  created_by    uuid not null references public.profiles(id) on delete cascade,
  body          text not null check (length(body) between 1 and 5000),
  media         jsonb not null default '[]'::jsonb check (jsonb_typeof(media) = 'array'),
  platforms     text[] not null default '{}',
  status        text not null default 'draft' check (status in ('draft','scheduled','publishing','published','failed')),
  scheduled_for timestamptz,
  published_at  timestamptz,
  error         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (status <> 'scheduled' or scheduled_for is not null)
);
create index sp_posts_subject_status_idx on public.sp_posts (subject_id, status);
create index sp_posts_due_idx on public.sp_posts (scheduled_for) where status = 'scheduled';
create index sp_posts_created_by_idx on public.sp_posts (created_by);
create trigger sp_posts_updated_at before update on public.sp_posts for each row execute function public.set_updated_at();

alter table public.sp_posts enable row level security;
create policy sp_posts_select on public.sp_posts for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy sp_posts_insert on public.sp_posts for insert to authenticated with check ((select public.has_subject_access(subject_id)) and created_by = (select auth.uid()) and status in ('draft','scheduled'));
-- users may edit and (re)schedule; moving a post to publishing/published/failed is the publisher's job (service role)
create policy sp_posts_update on public.sp_posts for update to authenticated using ((select public.has_subject_access(subject_id)) and status in ('draft','scheduled','failed')) with check ((select public.has_subject_access(subject_id)) and status in ('draft','scheduled'));
create policy sp_posts_delete on public.sp_posts for delete to authenticated using ((select public.has_subject_access(subject_id)) and status in ('draft','scheduled','failed'));
select public.apply_mfa_gate('public.sp_posts');

grant select, delete on public.sp_posts to authenticated;
grant insert (subject_id, created_by, body, media, platforms, status, scheduled_for) on public.sp_posts to authenticated;
grant update (body, media, platforms, status, scheduled_for) on public.sp_posts to authenticated;

-- Publisher (service role) claims due posts exactly once, even with concurrent workers.
create function public.sp_claim_due_posts(p_limit integer default 20) returns setof public.sp_posts
language sql security definer set search_path = '' as $$
  update public.sp_posts set status = 'publishing'
   where id in (select id from public.sp_posts where status = 'scheduled' and scheduled_for <= now()
                order by scheduled_for for update skip locked limit greatest(1, least(p_limit, 100)))
  returning *
$$;

insert into public.operation_pricing (operation, credit_cost, label, pack) values
  ('sp.generate_post', 0, 'Generate a post draft', 'social-posts'),
  ('sp.generate_image', 0, 'Generate a post image', 'social-posts')
on conflict (operation) do nothing;
