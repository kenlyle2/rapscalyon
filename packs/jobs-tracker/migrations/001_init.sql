create table public.jb_applications (
  id           uuid primary key default gen_random_uuid(),
  subject_id   uuid not null references public.subjects(id) on delete cascade,
  company      text not null check (length(company) between 1 and 200),
  title        text not null check (length(title) between 1 and 200),
  url          text check (url is null or url ~* '^https?://'),
  status       text not null default 'saved' check (status in ('saved','applied','interviewing','offer','rejected','withdrawn')),
  source       text,
  location     text,
  salary_min   integer check (salary_min >= 0),
  salary_max   integer check (salary_max >= 0),
  currency     char(3) not null default 'USD' check (currency = upper(currency)),
  applied_at   date,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (salary_max is null or salary_min is null or salary_max >= salary_min),
  unique (id, subject_id)
);
create index jb_applications_subject_status_idx on public.jb_applications (subject_id, status);
create trigger jb_applications_updated_at before update on public.jb_applications for each row execute function public.set_updated_at();

create table public.jb_application_events (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null,
  subject_id     uuid not null,
  kind           text not null check (kind in ('status_change','note','interview','contact','offer')),
  note           text,
  occurred_at    timestamptz not null default now(),
  foreign key (application_id, subject_id) references public.jb_applications (id, subject_id) on delete cascade
);
create index jb_application_events_app_idx on public.jb_application_events (application_id, subject_id, occurred_at desc);
create index jb_application_events_subject_idx on public.jb_application_events (subject_id);

-- every status change leaves an audit event
create function public.jb_log_status_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    insert into public.jb_application_events (application_id, subject_id, kind, note)
    values (new.id, new.subject_id, 'status_change', old.status || ' -> ' || new.status);
    if new.status = 'applied' and new.applied_at is null then new.applied_at := current_date; end if;
  end if;
  return new;
end $$;
create trigger jb_applications_status_log before update of status on public.jb_applications for each row execute function public.jb_log_status_change();

alter table public.jb_applications enable row level security;
alter table public.jb_application_events enable row level security;
create policy jb_applications_all on public.jb_applications for all to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy jb_application_events_select on public.jb_application_events for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy jb_application_events_insert on public.jb_application_events for insert to authenticated with check ((select public.has_subject_access(subject_id)) and kind <> 'status_change');
select public.apply_mfa_gate('public.jb_applications');
select public.apply_mfa_gate('public.jb_application_events');

grant select, delete on public.jb_applications to authenticated;
grant insert (subject_id, company, title, url, status, source, location, salary_min, salary_max, currency, applied_at, notes) on public.jb_applications to authenticated;
grant update (company, title, url, status, source, location, salary_min, salary_max, currency, applied_at, notes) on public.jb_applications to authenticated;
grant select on public.jb_application_events to authenticated;
grant insert (application_id, subject_id, kind, note, occurred_at) on public.jb_application_events to authenticated;

insert into public.operation_pricing (operation, credit_cost, label, pack) values
  ('jb.tailor_resume', 0, 'Tailor resume to a posting', 'jobs-tracker')
on conflict (operation) do nothing;
