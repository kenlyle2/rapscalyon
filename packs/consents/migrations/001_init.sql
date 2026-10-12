create table public.cn_consents (
  id              uuid primary key default gen_random_uuid(),
  subject_id      uuid not null references public.subjects(id) on delete cascade,
  created_by      uuid references public.profiles(id) on delete set null,
  person_id       uuid,
  purpose         text not null check (purpose ~ '^[a-z][a-z0-9_]{1,39}$'),
  person_key      text not null check (length(person_key) between 3 and 320 and person_key = lower(btrim(person_key))),
  action          text not null check (action in ('granted','withdrawn')),
  source          text not null check (source in ('web_form','sms_reply','verbal','written','import','other')),
  wording_version text,
  evidence        text check (length(evidence) <= 2000),
  occurred_at     timestamptz not null default clock_timestamp(),
  created_at      timestamptz not null default clock_timestamp(),
  -- the person must belong to the same subject; erasing the person keeps the ledger row
  foreign key (person_id, subject_id) references public.ppl_people (id, subject_id) on delete set null (person_id)
);
create index cn_consents_lookup_idx on public.cn_consents (subject_id, purpose, person_key, occurred_at desc, created_at desc);
create index cn_consents_created_by_idx on public.cn_consents (created_by);
create index cn_consents_person_idx on public.cn_consents (person_id, subject_id);

alter table public.cn_consents enable row level security;
create policy cn_consents_select on public.cn_consents for select to authenticated using ((select public.has_subject_access(subject_id)));
-- append only: a user records what happened for their own subject; there is no update or delete policy
create policy cn_consents_insert on public.cn_consents for insert to authenticated with check ((select public.has_subject_access(subject_id)) and created_by = (select auth.uid()));
select public.apply_mfa_gate('public.cn_consents');

grant select on public.cn_consents to authenticated;
grant insert (subject_id, created_by, person_id, purpose, person_key, action, source, wording_version, evidence, occurred_at) on public.cn_consents to authenticated;

-- True when the latest ledger row for this person and purpose is a grant. Runs as the caller, so row-level security limits it to subjects they can access.
create function public.cn_has_consent(p_subject uuid, p_purpose text, p_key text) returns boolean
language sql stable security invoker set search_path = '' as $$
  select coalesce((select c.action = 'granted' from public.cn_consents c
                    where c.subject_id = p_subject and c.purpose = p_purpose and c.person_key = lower(btrim(p_key))
                    order by c.occurred_at desc, c.created_at desc, c.id desc limit 1), false)
$$;
grant execute on function public.cn_has_consent(uuid, text, text) to authenticated;

-- Service role: record a withdrawal that arrived outside a user session (for example an inbound STOP reply). Idempotent: no new row when the latest is already a withdrawal.
create function public.cn_withdraw(p_subject uuid, p_purpose text, p_key text, p_source text default 'sms_reply', p_evidence text default null) returns boolean
language plpgsql security definer set search_path = '' as $$
declare k text := lower(btrim(p_key));
begin
  if exists (select 1 from public.cn_consents c where c.subject_id = p_subject and c.purpose = p_purpose and c.person_key = k and c.action = 'granted')
     and not coalesce((select c.action = 'withdrawn' from public.cn_consents c
                        where c.subject_id = p_subject and c.purpose = p_purpose and c.person_key = k
                        order by c.occurred_at desc, c.created_at desc, c.id desc limit 1), false) then
    insert into public.cn_consents (subject_id, purpose, person_key, action, source, evidence) values (p_subject, p_purpose, k, 'withdrawn', p_source, p_evidence);
    return true;
  end if;
  return false;
end $$;
revoke all on function public.cn_withdraw(uuid, text, text, text, text) from public, anon, authenticated;
