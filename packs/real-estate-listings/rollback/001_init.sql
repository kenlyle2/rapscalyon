delete from public.operation_pricing where pack = 'real-estate-listings';
drop table if exists public.rel_listing_photos;
drop table if exists public.rel_listings;
drop function if exists public.rel_enforce_listing_limit();
drop function if exists public.rel_set_listed_at();
