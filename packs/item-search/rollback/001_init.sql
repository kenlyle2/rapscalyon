-- is_claim_outbox returns the is_outbox row type, so it must go before the table.
drop function if exists public.is_claim_outbox(integer);
drop table if exists public.is_outbox;
drop table if exists public.is_dispatches;
drop table if exists public.is_candidates;
drop table if exists public.is_profiles;
drop function if exists public.is_emit(uuid, text, uuid);
drop function if exists public.is_enforce_profile_limit();
drop function if exists public.is_profile_changed();
drop function if exists public.is_dispatch_approved();
drop function if exists public.is_accept_candidate(uuid);
drop function if exists public.is_dismiss_candidate(uuid);
drop function if exists public.is_set_dispatch_overrides(uuid, jsonb);
drop function if exists public.is_approve_dispatch(uuid, integer);
drop function if exists public.is_cancel_dispatch(uuid);
drop function if exists public.is_claim_next_dispatch();
drop function if exists public.is_complete_dispatch(uuid, boolean, text);
