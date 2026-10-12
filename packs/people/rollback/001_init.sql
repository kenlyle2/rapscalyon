drop function if exists public.ppl_is_self(uuid);
drop function if exists public.ppl_unlink_login(uuid);
drop function if exists public.ppl_claim(uuid);
drop function if exists public.ppl_invite_login(uuid);
drop table if exists public.ppl_external_refs;
drop table if exists public.ppl_claims;
drop table if exists public.ppl_people;
drop function if exists public.ppl_check_assignee();
