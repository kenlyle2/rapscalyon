drop function if exists public.cal_remove_source(uuid, text, text);
drop function if exists public.cal_upsert_event(uuid, text, text, text, text, timestamptz, timestamptz, boolean, uuid);
drop table if exists public.cal_events;
