-- An event can be marked missed (it happened, the person did not take part). Counting misses by kind over a window is the signal other features act on.
alter table public.cal_events drop constraint cal_events_status_check;
alter table public.cal_events add constraint cal_events_status_check check (status in ('scheduled','done','cancelled','missed'));

-- Missed events by kind in [p_from, p_to): marked missed, or still scheduled although they ended before now. Runs as the caller, so row-level security limits it to subjects they can access.
create function public.cal_missed_counts(p_subject uuid, p_from timestamptz, p_to timestamptz, p_person uuid default null) returns table (kind text, missed bigint)
language sql stable security invoker set search_path = '' as $$
  select e.kind, count(*) from public.cal_events e
   where e.subject_id = p_subject and e.starts_at >= p_from and e.starts_at < p_to
     and (p_person is null or e.person_id = p_person)
     and (e.status = 'missed' or (e.status = 'scheduled' and e.ends_at < now()))
   group by e.kind order by e.kind
$$;
grant execute on function public.cal_missed_counts(uuid, timestamptz, timestamptz, uuid) to authenticated;
