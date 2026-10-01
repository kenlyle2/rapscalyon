create table public.ind_details (
  subject_id uuid primary key references public.subjects(id) on delete cascade,
  headline   text,
  location   text,
  links      jsonb not null default '[]'::jsonb check (jsonb_typeof(links) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger ind_details_updated_at before update on public.ind_details for each row execute function public.set_updated_at();

-- a details row only for subjects of kind 'individual'
create function public.ind_check_kind() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.subjects s where s.id = new.subject_id and s.kind = 'individual') then
    raise exception 'ind_details requires a subject of kind individual' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger ind_details_kind before insert or update of subject_id on public.ind_details for each row execute function public.ind_check_kind();

-- plan limit on how many individuals an owner may create (hooks the core subjects table; trigger is pack-prefixed)
create function public.ind_enforce_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_tier text; v_limit integer; v_count integer;
begin
  if new.kind <> 'individual' then return new; end if;
  select tier into v_tier from public.profiles where id = new.owner_id;
  v_limit := public.get_plan_limit(coalesce(v_tier, 'free'), 'ind_max_subjects', 1);
  select count(*) into v_count from public.subjects where owner_id = new.owner_id and kind = 'individual';
  if v_count >= v_limit then
    raise exception 'ind_max_subjects limit reached (%)', v_limit using errcode = '53400';
  end if;
  return new;
end $$;
create trigger ind_subjects_limit before insert on public.subjects for each row execute function public.ind_enforce_limit();

alter table public.ind_details enable row level security;
create policy ind_details_select on public.ind_details for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy ind_details_insert on public.ind_details for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy ind_details_update on public.ind_details for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy ind_details_delete on public.ind_details for delete to authenticated using ((select public.is_subject_owner(subject_id)));
select public.apply_mfa_gate('public.ind_details');

grant select, delete on public.ind_details to authenticated;
grant insert (subject_id, headline, location, links) on public.ind_details to authenticated;
grant update (headline, location, links) on public.ind_details to authenticated;
