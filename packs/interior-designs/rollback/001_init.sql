drop table if exists public.idg_designs;
drop function if exists public.idg_request_design(uuid, text, text, text, text);
drop function if exists public.idg_mark_started(uuid, text);
drop function if exists public.idg_complete(uuid, text[]);
drop function if exists public.idg_fail(uuid, text);
drop function if exists public.idg_record_design(uuid, uuid, text, text, text, text, text, text[]);
drop function if exists public.idg_check_kind();
delete from public.it_items where kind = 'interior_design';
