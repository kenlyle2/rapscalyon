drop table if exists public.qrg_codes;
drop function if exists public.qrg_request(uuid, text, text);
drop function if exists public.qrg_mark_started(uuid, text);
drop function if exists public.qrg_complete(uuid, text[]);
drop function if exists public.qrg_fail(uuid, text);
drop function if exists public.qrg_record(uuid, uuid, text, text, text, text[]);
drop function if exists public.qrg_check_kind();
delete from public.it_items where kind = 'qr_code';
drop function if exists public.qrg_valid_keys(text[], integer);
