drop table if exists public.igen_generations;
drop function if exists public.igen_request(uuid, text, text, text, numeric, integer, integer);
drop function if exists public.igen_mark_started(uuid, text);
drop function if exists public.igen_complete(uuid, text[]);
drop function if exists public.igen_fail(uuid, text);
drop function if exists public.igen_record(uuid, uuid, text, text, text, text, numeric, integer, integer, text[]);
drop function if exists public.igen_check_kind();
delete from public.it_items where kind = 'image_generation';
drop function if exists public.igen_valid_keys(text[], integer);
