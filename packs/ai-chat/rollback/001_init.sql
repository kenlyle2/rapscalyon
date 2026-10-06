drop table if exists public.cht_messages;
drop table if exists public.cht_chats;
drop function if exists public.cht_start(uuid, uuid, text, text, text, text);
drop function if exists public.cht_append(uuid, text, text, text, integer);
drop function if exists public.cht_check_kind();
delete from public.it_items where kind = 'chat';
