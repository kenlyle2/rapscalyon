drop function if exists public.team_remove_member(uuid, uuid);
drop function if exists public.team_accept(uuid);
drop function if exists public.team_invite(uuid, text, text);
drop table if exists public.team_invites;
