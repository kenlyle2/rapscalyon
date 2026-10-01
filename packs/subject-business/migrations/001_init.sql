create table public.biz_details (
  subject_id uuid primary key references public.subjects(id) on delete cascade,
  category   text,
  phone      text,
  website    text,
  address    jsonb not null default '{}'::jsonb check (jsonb_typeof(address) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger biz_details_updated_at before update on public.biz_details for each row execute function public.set_updated_at();

-- a details row only for subjects of kind 'business'
create function public.biz_check_kind() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.subjects s where s.id = new.subject_id and s.kind = 'business') then
    raise exception 'biz_details requires a subject of kind business' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger biz_details_kind before insert or update of subject_id on public.biz_details for each row execute function public.biz_check_kind();

-- plan limit on how many businesses an owner may create (hooks the core subjects table; trigger is pack-prefixed)
create function public.biz_enforce_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_tier text; v_limit integer; v_count integer;
begin
  if new.kind <> 'business' then return new; end if;
  select tier into v_tier from public.profiles where id = new.owner_id;
  v_limit := public.get_plan_limit(coalesce(v_tier, 'free'), 'biz_max_subjects', 1);
  select count(*) into v_count from public.subjects where owner_id = new.owner_id and kind = 'business';
  if v_count >= v_limit then
    raise exception 'biz_max_subjects limit reached (%)', v_limit using errcode = '53400';
  end if;
  return new;
end $$;
create trigger biz_subjects_limit before insert on public.subjects for each row execute function public.biz_enforce_limit();

alter table public.biz_details enable row level security;
create policy biz_details_select on public.biz_details for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy biz_details_insert on public.biz_details for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy biz_details_update on public.biz_details for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy biz_details_delete on public.biz_details for delete to authenticated using ((select public.is_subject_owner(subject_id)));
select public.apply_mfa_gate('public.biz_details');

grant select, delete on public.biz_details to authenticated;
grant insert (subject_id, category, phone, website, address) on public.biz_details to authenticated;
grant update (category, phone, website, address) on public.biz_details to authenticated;
