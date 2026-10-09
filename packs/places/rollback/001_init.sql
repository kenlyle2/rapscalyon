drop function if exists public.geo_nearest(double precision, double precision);
drop function if exists public.geo_resolve(text, double precision, double precision);
drop function if exists public.geo_search(text, integer);
drop view if exists public.geo_places_full;
drop table if exists public.geo_places;
drop function if exists public.geo_distance_km(double precision, double precision, double precision, double precision);
drop function if exists public.geo_key(text);
