drop trigger if exists biz_subjects_limit on public.subjects;
drop table if exists public.biz_details;
drop function if exists public.biz_enforce_limit();
drop function if exists public.biz_check_kind();
