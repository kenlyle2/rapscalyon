drop table if exists public.cwy_sources;
drop function if exists public.cwy_attach(uuid, text, text, text, text, text, text);
drop function if exists public.cwy_mark_ingested(uuid);
