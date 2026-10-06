drop table if exists public.mgn_tracks;
drop function if exists public.mgn_request(uuid, text, text, text, integer);
drop function if exists public.mgn_mark_started(uuid, text);
drop function if exists public.mgn_complete(uuid, text[]);
drop function if exists public.mgn_fail(uuid, text);
drop function if exists public.mgn_record(uuid, uuid, text, text, text, text, integer, text[]);
drop function if exists public.mgn_check_kind();
delete from public.it_items where kind = 'music_track';
drop function if exists public.mgn_valid_keys(text[], integer);
