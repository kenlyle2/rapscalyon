drop trigger if exists ind_subjects_limit on public.subjects;
drop table if exists public.ind_details;
drop function if exists public.ind_enforce_limit();
drop function if exists public.ind_check_kind();
