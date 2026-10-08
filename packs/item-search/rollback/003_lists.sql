drop function if exists public.is_remove_from_list(uuid, uuid);
drop function if exists public.is_add_to_list(uuid, uuid);
drop function if exists public.is_delete_list(uuid);
drop function if exists public.is_rename_list(uuid, text);
drop function if exists public.is_create_list(uuid, text);
drop table if exists public.is_list_items;
drop table if exists public.is_lists;
