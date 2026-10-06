drop table if exists public.cwr_pieces;
drop function if exists public.cwr_record(uuid, uuid, text, text, text, text, integer, text, integer);
drop function if exists public.cwr_check_kind();
delete from public.it_items where kind = 'content_piece';
drop function if exists public.cwr_valid_keys(text[], integer);
