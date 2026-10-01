drop function if exists public.lp_stuck_outbox();
drop function if exists public.lp_claim_outbox(integer);
drop function if exists public.lp_enqueue(uuid, text, jsonb);
drop table if exists public.lp_preferences;
drop table if exists public.lp_outbox;
