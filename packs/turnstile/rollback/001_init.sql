drop function if exists public.ts_purge_old(integer);
drop function if exists public.ts_recent_failures(text, integer);
drop function if exists public.ts_record_failure(text, text, text, uuid);
drop table if exists public.ts_failures;
