-- places 0.1.0: a read-only gazetteer. Rows are loaded by migrations (tools/load-canton.mjs writes them); users and the API can only read.
create extension if not exists pg_trgm schema extensions;

-- Lowercase, accents and punctuation removed, single spaces: the form every name is compared in ("Gutiérrez Braun" -> "gutierrez braun").
create function public.geo_key(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select trim(regexp_replace(translate(lower(coalesce(p, '')), 'áéíóúüñàèìòù', 'aeiouunaeiou'), '[^a-z0-9]+', ' ', 'g'))
$$;

-- Great-circle distance in kilometres (haversine); null when any coordinate is missing.
create function public.geo_distance_km(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision) returns double precision
language sql immutable parallel safe set search_path = '' as $$
  select case when lat1 is null or lon1 is null or lat2 is null or lon2 is null then null
    else 12742 * asin(sqrt(least(1, power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2))))
  end
$$;

create table public.geo_places (
  id        bigint generated always as identity primary key,
  osm_ref   text unique check (osm_ref is null or osm_ref ~ '^[nwr][0-9]+$'),   -- n/w/r + OpenStreetMap id; null for places added by hand
  name      text not null check (length(name) between 1 and 120),
  kind      text not null check (kind in ('province', 'canton', 'district', 'locality')),
  parent_id bigint references public.geo_places (id) on delete cascade,
  lat       double precision not null check (lat between -90 and 90),
  lon       double precision not null check (lon between -180 and 180),
  aliases   text[] not null default '{}',   -- other spellings people use ("Jabillo" for "Jabillos")
  name_key  text generated always as (public.geo_key(name)) stored,
  check ((kind = 'province') = (parent_id is null))
);
create index geo_places_parent_idx on public.geo_places (parent_id);
create index geo_places_key_idx on public.geo_places (name_key);
create index geo_places_trgm_idx on public.geo_places using gin (name_key extensions.gin_trgm_ops);

alter table public.geo_places enable row level security;
create policy geo_places_read on public.geo_places for select to authenticated using (true);
select public.apply_mfa_gate('public.geo_places');
grant select on public.geo_places to authenticated;

-- Each place with the province, canton and district it sits in (a district has no district above it, and so on).
create view public.geo_places_full with (security_invoker = true) as
select p.id, p.name, p.kind, p.lat, p.lon, p.aliases, p.name_key,
  case p.kind when 'locality' then a1.name when 'district' then p.name end as district,
  case p.kind when 'locality' then a2.name when 'district' then a1.name when 'canton' then p.name end as canton,
  case p.kind when 'locality' then a3.name when 'district' then a2.name when 'canton' then a1.name when 'province' then p.name end as province
from public.geo_places p
left join public.geo_places a1 on a1.id = p.parent_id
left join public.geo_places a2 on a2.id = a1.parent_id
left join public.geo_places a3 on a3.id = a2.parent_id;
grant select on public.geo_places_full to authenticated;

-- Type-ahead: places whose name starts with, equals or resembles the text (typos and missing accents tolerated), best first.
create function public.geo_search(p_q text, p_limit integer default 8)
returns table (id bigint, name text, kind text, district text, canton text, province text, lat double precision, lon double precision, score real)
language sql stable set search_path = '' as $$
  with q as (select public.geo_key(p_q) k)
  select f.id, f.name, f.kind, f.district, f.canton, f.province, f.lat, f.lon,
    greatest(
      case when f.name_key = q.k then 3.0 when f.name_key like q.k || '%' then 2.0 else 0 end,
      coalesce((select max(case when public.geo_key(a) = q.k then 3.0 else 0 end) from unnest(f.aliases) a), 0),
      extensions.similarity(f.name_key, q.k)
    )::real as score
  from public.geo_places_full f, q
  where length(q.k) >= 2 and (f.name_key like q.k || '%' or f.name_key operator(extensions.%) q.k or exists (select 1 from unnest(f.aliases) a where public.geo_key(a) = q.k))
  order by score desc, case f.kind when 'district' then 0 when 'locality' then 1 when 'canton' then 2 else 3 end, f.name
  limit greatest(1, least(coalesce(p_limit, 8), 50))
$$;

-- The place named in free text ("Lourdes de Sabalito", "ubicado en Cañas Gordas"): the longest name found as whole words wins; on a tie the
-- one nearest to p_near_* (the buyer's home), then districts before localities. Null when no place is named.
create function public.geo_resolve(p_text text, p_near_lat double precision default null, p_near_lon double precision default null)
returns table (place_id bigint, name text, kind text, district text, canton text, lat double precision, lon double precision)
language sql stable set search_path = '' as $$
  with t as (select ' ' || public.geo_key(p_text) || ' ' k)
  select f.id, f.name, f.kind, f.district, f.canton, f.lat, f.lon
  from public.geo_places_full f, t
  where f.kind <> 'province'
    and (t.k like '% ' || f.name_key || ' %' or exists (select 1 from unnest(f.aliases) a where t.k like '% ' || public.geo_key(a) || ' %'))
  order by length(f.name_key) desc, public.geo_distance_km(f.lat, f.lon, p_near_lat, p_near_lon) nulls last,
           case f.kind when 'district' then 0 when 'locality' then 1 else 2 end, f.id
  limit 1
$$;

-- "Use my current location": the closest named locality to a point, with how far it is.
create function public.geo_nearest(p_lat double precision, p_lon double precision)
returns table (place_id bigint, name text, district text, canton text, province text, lat double precision, lon double precision, distance_km double precision)
language sql stable set search_path = '' as $$
  select f.id, f.name, f.district, f.canton, f.province, f.lat, f.lon, public.geo_distance_km(f.lat, f.lon, p_lat, p_lon)
  from public.geo_places_full f
  where f.kind in ('locality', 'district') and p_lat between -90 and 90 and p_lon between -180 and 180
  order by public.geo_distance_km(f.lat, f.lon, p_lat, p_lon), f.id
  limit 1
$$;

revoke all on function public.geo_key(text), public.geo_distance_km(double precision, double precision, double precision, double precision),
  public.geo_search(text, integer), public.geo_resolve(text, double precision, double precision), public.geo_nearest(double precision, double precision) from public, anon;
grant execute on function public.geo_search(text, integer), public.geo_resolve(text, double precision, double precision), public.geo_nearest(double precision, double precision) to authenticated, service_role;
grant execute on function public.geo_key(text), public.geo_distance_km(double precision, double precision, double precision, double precision) to authenticated, service_role;   -- pure helpers; the invoker functions above call them as the user
