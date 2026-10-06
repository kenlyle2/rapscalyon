drop table if exists public.itr_jobs;
drop function if exists public.itr_request(uuid, text, text);
drop function if exists public.itr_mark_started(uuid, text);
drop function if exists public.itr_complete(uuid, text[]);
drop function if exists public.itr_fail(uuid, text);
drop function if exists public.itr_record(uuid, uuid, text, text, text, text[]);
drop function if exists public.itr_check_kind();
delete from public.it_items where kind = 'image_transform';
drop function if exists public.itr_valid_keys(text[], integer);
