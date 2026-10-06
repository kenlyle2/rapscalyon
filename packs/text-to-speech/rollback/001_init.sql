drop table if exists public.tts_clips;
drop function if exists public.tts_record(uuid, uuid, text, text, text, text, text, text, integer);
drop function if exists public.tts_check_kind();
delete from public.it_items where kind = 'speech_clip';
drop function if exists public.tts_valid_keys(text[], integer);
