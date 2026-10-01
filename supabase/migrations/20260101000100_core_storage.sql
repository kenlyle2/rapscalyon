-- RapScalYon core storage 0.1.0 (AGPL-3.0-or-later). Idempotent; applied by `rapscalyon.py core` after the foundation.
-- One private bucket, `media`. Object paths MUST start with the subject id: <subject_id>/<anything>.
-- Access follows the same rule as every pack table: subject owner or accepted member (public.has_subject_access).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 10485760, array['image/jpeg','image/png','image/webp','image/gif','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.storage_subject_of(p_name text) returns uuid
language sql immutable set search_path = '' as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_name, '/', 1)::uuid end
$$;
revoke execute on function public.storage_subject_of(text) from public;
grant execute on function public.storage_subject_of(text) to authenticated, service_role;

drop policy if exists media_select on storage.objects;
drop policy if exists media_insert on storage.objects;
drop policy if exists media_update on storage.objects;
drop policy if exists media_delete on storage.objects;
create policy media_select on storage.objects for select to authenticated
  using (bucket_id = 'media' and (select public.has_subject_access(public.storage_subject_of(name))));
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (select public.has_subject_access(public.storage_subject_of(name))));
create policy media_update on storage.objects for update to authenticated
  using (bucket_id = 'media' and (select public.has_subject_access(public.storage_subject_of(name))))
  with check (bucket_id = 'media' and (select public.has_subject_access(public.storage_subject_of(name))));
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (select public.has_subject_access(public.storage_subject_of(name))));
