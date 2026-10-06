drop table if exists public.ytc_pieces;
drop function if exists public.ytc_record(uuid, uuid, text, text, text, text, text, text, jsonb, integer);
drop function if exists public.ytc_check_kind();
delete from public.it_items where kind = 'youtube_content';
drop function if exists public.ytc_valid_keys(text[], integer);
