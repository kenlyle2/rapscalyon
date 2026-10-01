create table public.rel_listings (
  id            uuid primary key default gen_random_uuid(),
  subject_id    uuid not null references public.subjects(id) on delete cascade,
  created_by    uuid not null references public.profiles(id) on delete cascade,
  status        text not null default 'draft' check (status in ('draft','active','pending','sold','withdrawn')),
  title         text not null check (length(title) between 1 and 200),
  description   text,
  property_type text check (property_type in ('house','apartment','condo','townhouse','land','commercial','other')),
  address       jsonb not null default '{}'::jsonb check (jsonb_typeof(address) = 'object'),
  price_minor   bigint check (price_minor >= 0),
  currency      char(3) not null default 'USD' check (currency = upper(currency)),
  bedrooms      smallint check (bedrooms >= 0),
  bathrooms     numeric(3,1) check (bathrooms >= 0),
  area_sqm      numeric(10,2) check (area_sqm > 0),
  listed_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (id, subject_id)
);
create index rel_listings_subject_status_idx on public.rel_listings (subject_id, status);
create index rel_listings_created_by_idx on public.rel_listings (created_by);
create trigger rel_listings_updated_at before update on public.rel_listings for each row execute function public.set_updated_at();

create table public.rel_listing_photos (
  id           uuid primary key default gen_random_uuid(),
  listing_id   uuid not null,
  subject_id   uuid not null,
  storage_path text not null check (length(storage_path) between 1 and 500),
  position     smallint not null default 0 check (position >= 0),
  alt_text     text,
  created_at   timestamptz not null default now(),
  -- composite FK keeps photo.subject_id honest, so the policy needs no join
  foreign key (listing_id, subject_id) references public.rel_listings (id, subject_id) on delete cascade,
  unique (listing_id, position)
);
create index rel_listing_photos_subject_idx on public.rel_listing_photos (subject_id);

create function public.rel_set_listed_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'active' and (tg_op = 'INSERT' or old.status is distinct from 'active') and new.listed_at is null then
    new.listed_at := now();
  end if;
  return new;
end $$;
create trigger rel_listings_listed_at before insert or update of status on public.rel_listings for each row execute function public.rel_set_listed_at();

create function public.rel_enforce_listing_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_tier text; v_limit integer; v_count integer;
begin
  if new.status not in ('active','pending') then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('active','pending') then return new; end if;
  select p.tier into v_tier from public.subjects s join public.profiles p on p.id = s.owner_id where s.id = new.subject_id;
  v_limit := public.get_plan_limit(coalesce(v_tier, 'free'), 'rel_max_active_listings', 10);
  select count(*) into v_count from public.rel_listings where subject_id = new.subject_id and status in ('active','pending') and id <> new.id;
  if v_count >= v_limit then
    raise exception 'rel_max_active_listings limit reached (%)', v_limit using errcode = '53400';
  end if;
  return new;
end $$;
create trigger rel_listings_limit before insert or update of status on public.rel_listings for each row execute function public.rel_enforce_listing_limit();

alter table public.rel_listings enable row level security;
alter table public.rel_listing_photos enable row level security;
create policy rel_listings_select on public.rel_listings for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy rel_listings_insert on public.rel_listings for insert to authenticated with check ((select public.has_subject_access(subject_id)) and created_by = (select auth.uid()));
create policy rel_listings_update on public.rel_listings for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy rel_listings_delete on public.rel_listings for delete to authenticated using ((select public.is_subject_owner(subject_id)));
create policy rel_listing_photos_all on public.rel_listing_photos for all to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.rel_listings');
select public.apply_mfa_gate('public.rel_listing_photos');

grant select, delete on public.rel_listings to authenticated;
grant insert (subject_id, created_by, status, title, description, property_type, address, price_minor, currency, bedrooms, bathrooms, area_sqm) on public.rel_listings to authenticated;
grant update (status, title, description, property_type, address, price_minor, currency, bedrooms, bathrooms, area_sqm) on public.rel_listings to authenticated;
grant select, delete on public.rel_listing_photos to authenticated;
grant insert (listing_id, subject_id, storage_path, position, alt_text) on public.rel_listing_photos to authenticated;
grant update (position, alt_text) on public.rel_listing_photos to authenticated;

-- metered operations; the operator sets the real price (0 until then)
insert into public.operation_pricing (operation, credit_cost, label, pack) values
  ('rel.generate_description', 0, 'Generate listing description', 'real-estate-listings'),
  ('rel.enhance_photo', 0, 'Enhance listing photo', 'real-estate-listings')
on conflict (operation) do nothing;
