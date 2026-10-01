drop table if exists public.it_item_events;
drop table if exists public.it_items;
drop function if exists public.it_log_event(uuid, text, text);
drop function if exists public.it_enforce_item_limit();
