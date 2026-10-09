update public.geo_places set aliases = '{}' where name in ('Jabillos', 'Gutiérrez Braun', 'Aguabuena');
delete from public.geo_places where osm_ref = 'n9802146346';
