-- Jabillos is a named hamlet in OpenStreetMap that sits just outside the Coto Brus boundary polygon, so the canton loader skipped it; local people
-- count it as part of the San Vito area. It is filed under Limoncito, the nearest district centre (unverified: check against IGN).
insert into public.geo_places (osm_ref, name, kind, parent_id, lat, lon)
select 'n9802146346', 'Jabillos', 'locality', (select id from public.geo_places where name = 'Limoncito' and kind = 'district'), 8.93522, -83.09167
on conflict (osm_ref) do nothing;

-- Spellings people actually write for Coto Brus places (OpenStreetMap has "Jabillos", the district is officially "Gutiérrez Braun").
update public.geo_places set aliases = (select array(select distinct unnest(aliases || array['Jabillo']))) where name = 'Jabillos' and kind = 'locality';
update public.geo_places set aliases = (select array(select distinct unnest(aliases || array['Gutierrez Brown', 'Gutiérrez Brown']))) where name = 'Gutiérrez Braun' and kind = 'district';
update public.geo_places set aliases = (select array(select distinct unnest(aliases || array['Agua Buena']))) where name = 'Aguabuena' and kind in ('district', 'locality');
