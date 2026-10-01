delete from public.operation_pricing where pack = 'jobs-tracker';
drop table if exists public.jb_application_events;
drop table if exists public.jb_applications;
drop function if exists public.jb_log_status_change();
