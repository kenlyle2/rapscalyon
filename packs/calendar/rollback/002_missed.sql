drop function if exists public.cal_missed_counts(uuid, timestamptz, timestamptz, uuid);
-- 'missed' does not exist in 0.1.0; those rows become 'cancelled'
update public.cal_events set status = 'cancelled' where status = 'missed';
alter table public.cal_events drop constraint cal_events_status_check;
alter table public.cal_events add constraint cal_events_status_check check (status in ('scheduled','done','cancelled'));
