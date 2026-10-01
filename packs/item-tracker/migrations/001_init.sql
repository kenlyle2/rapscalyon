-- item-tracker: the base class. A child pack keys a 1:1 table on it_items (id, subject_id) and adds typed columns.
create table public.it_items (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  kind        text not null check (kind ~ '^[a-z][a-z0-9_]{1,29}$'),
  title       text not null check (length(title) between 1 and 200),
  url         text check (url is null or url ~* '^https?://'),
  source      text check (source is null or length(source) <= 100),
  notes       text check (notes is null or length(notes) <= 20000),
  archived_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, subject_id)
);
create index it_items_subject_kind_idx on public.it_items (subject_id, kind, created_at desc);
create trigger it_items_updated_at before update on public.it_items for each row execute function public.set_updated_at();

create table public.it_item_events (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null,
  subject_id  uuid not null,
  kind        text not null check (kind ~ '^[a-z][a-z0-9_]{1,29}$'),
  note        text check (note is null or length(note) <= 5000),
  occurred_at timestamptz not null default now(),
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index it_item_events_item_idx on public.it_item_events (item_id, subject_id, occurred_at desc);
create index it_item_events_subject_idx on public.it_item_events (subject_id);

-- Plan cap on unarchived items per subject. Service-role and migration code (no auth.uid()) is exempt.
create function public.it_enforce_item_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_tier text; v_limit integer; v_count integer;
begin
  if (select auth.uid()) is null then return new; end if;
  select p.tier into v_tier from public.subjects s join public.profiles p on p.id = s.owner_id where s.id = new.subject_id;
  v_limit := public.get_plan_limit(coalesce(v_tier, 'free'), 'it_max_items', 100);
  select count(*) into v_count from public.it_items where subject_id = new.subject_id and archived_at is null;
  if v_count >= v_limit then
    raise exception 'it_max_items limit reached (%)', v_limit using errcode = '53400';
  end if;
  return new;
end $$;
create trigger it_items_limit before insert on public.it_items for each row execute function public.it_enforce_item_limit();

-- Server-side event writer for child packs' triggers. Not executable by API roles, so clients cannot forge system events.
create function public.it_log_event(p_item uuid, p_kind text, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.it_item_events (item_id, subject_id, kind, note)
  select i.id, i.subject_id, p_kind, p_note from public.it_items i where i.id = p_item;
end $$;

alter table public.it_items enable row level security;
alter table public.it_item_events enable row level security;
create policy it_items_select on public.it_items for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy it_items_insert on public.it_items for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy it_items_update on public.it_items for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy it_items_delete on public.it_items for delete to authenticated using ((select public.is_subject_owner(subject_id)));
create policy it_item_events_select on public.it_item_events for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy it_item_events_insert on public.it_item_events for insert to authenticated with check ((select public.has_subject_access(subject_id)) and kind not in ('status_change', 'system'));
select public.apply_mfa_gate('public.it_items');
select public.apply_mfa_gate('public.it_item_events');

grant select, delete on public.it_items to authenticated;
grant insert (subject_id, kind, title, url, source, notes) on public.it_items to authenticated;
grant update (title, url, source, notes, archived_at) on public.it_items to authenticated;
grant select on public.it_item_events to authenticated;
grant insert (item_id, subject_id, kind, note, occurred_at) on public.it_item_events to authenticated;
