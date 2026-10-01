delete from public.operation_pricing where pack = 'social-posts';
drop function if exists public.sp_claim_due_posts(integer);
drop table if exists public.sp_posts;
