drop table if exists public.vtr_transcriptions;
drop function if exists public.vtr_request(uuid, text);
drop function if exists public.vtr_mark_started(uuid, text);
drop function if exists public.vtr_complete(uuid, text, text);
drop function if exists public.vtr_fail(uuid, text);
drop function if exists public.vtr_record(uuid, uuid, text, text, text, text);
drop function if exists public.vtr_check_kind();
delete from public.it_items where kind = 'voice_transcription';
drop function if exists public.vtr_valid_keys(text[], integer);
