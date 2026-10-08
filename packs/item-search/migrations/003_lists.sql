-- item-search 0.3.0: user-managed lists (Favorites, 4x4s, For Mom, ...). A candidate can be on several lists; a list belongs to one subject.
-- Reads go through row-level security; every change goes through the functions below, which check subject access and the MFA gate.
create table public.is_lists (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects (id) on delete cascade,
  name       text not null check (length(btrim(name)) between 1 and 60),
  created_at timestamptz not null default now(),
  unique (id, subject_id)
);
create unique index is_lists_subject_name_key on public.is_lists (subject_id, lower(btrim(name)));
create table public.is_list_items (
  list_id      uuid not null,
  candidate_id uuid not null references public.is_candidates (id) on delete cascade,
  subject_id   uuid not null references public.subjects (id) on delete cascade,
  added_at     timestamptz not null default now(),
  primary key (list_id, candidate_id),
  foreign key (list_id, subject_id) references public.is_lists (id, subject_id) on delete cascade
);
create index is_list_items_candidate_idx on public.is_list_items (candidate_id);
create index is_list_items_subject_idx on public.is_list_items (subject_id);
create index is_list_items_list_subject_idx on public.is_list_items (list_id, subject_id);
alter table public.is_lists enable row level security;
alter table public.is_list_items enable row level security;
create policy is_lists_select on public.is_lists for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy is_list_items_select on public.is_list_items for select to authenticated using ((select public.has_subject_access(subject_id)));
grant select on public.is_lists, public.is_list_items to authenticated;
select public.apply_mfa_gate('public.is_lists');
select public.apply_mfa_gate('public.is_list_items');

create function public.is_create_list(p_subject uuid, p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_name text := btrim(coalesce(p_name, ''));
begin
  if (select auth.uid()) is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if length(v_name) = 0 or length(v_name) > 60 then raise exception 'a list name is 1 to 60 characters' using errcode = '23514'; end if;
  if (select count(*) from public.is_lists where subject_id = p_subject) >= 50 then raise exception 'at most 50 lists' using errcode = '23514'; end if;
  select id into v_id from public.is_lists where subject_id = p_subject and lower(btrim(name)) = lower(v_name);
  if v_id is null then insert into public.is_lists (subject_id, name) values (p_subject, v_name) returning id into v_id; end if;
  return v_id;
end $$;

create function public.is_rename_list(p_list uuid, p_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.is_lists where id = p_list for update;
  if v_subject is null or (select auth.uid()) is null or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.is_lists set name = btrim(p_name) where id = p_list;
end $$;

create function public.is_delete_list(p_list uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.is_lists where id = p_list for update;
  if v_subject is null or (select auth.uid()) is null or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from public.is_lists where id = p_list;   -- only the list and its memberships; the candidates stay
end $$;

create function public.is_add_to_list(p_list uuid, p_candidate uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid; v_cand_subject uuid;
begin
  select subject_id into v_subject from public.is_lists where id = p_list;
  select subject_id into v_cand_subject from public.is_candidates where id = p_candidate;
  if v_subject is null or v_cand_subject is distinct from v_subject or (select auth.uid()) is null
     or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.is_list_items (list_id, candidate_id, subject_id) values (p_list, p_candidate, v_subject) on conflict do nothing;
end $$;

create function public.is_remove_from_list(p_list uuid, p_candidate uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid;
begin
  select subject_id into v_subject from public.is_lists where id = p_list;
  if v_subject is null or (select auth.uid()) is null or not public.has_subject_access(v_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from public.is_list_items where list_id = p_list and candidate_id = p_candidate;
end $$;

revoke all on function public.is_create_list(uuid, text), public.is_rename_list(uuid, text), public.is_delete_list(uuid),
  public.is_add_to_list(uuid, uuid), public.is_remove_from_list(uuid, uuid) from public, anon;
grant execute on function public.is_create_list(uuid, text), public.is_rename_list(uuid, text), public.is_delete_list(uuid),
  public.is_add_to_list(uuid, uuid), public.is_remove_from_list(uuid, uuid) to authenticated;
