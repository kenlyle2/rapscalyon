# places

A read-only gazetteer for Costa Rica: provinces, cantons, districts and named localities with coordinates, plus the functions other packs use to turn a place name, or a phone's location, into coordinates and a distance.

Loaded today: Puntarenas > Coto Brus (6 districts, about 100 localities). Add another canton with `tools/load-canton.mjs` (below).

## What it gives you

| Function | Use |
|---|---|
| `geo_search(text, limit)` | Type-ahead for a form: matches prefixes and typos, ignores accents ("gutierrez brown" finds Gutiérrez Braun). |
| `geo_resolve(text, near_lat, near_lon)` | The place named in free text ("Lourdes de Sabalito"). Longest name wins; ties go to the place nearest the buyer, then districts before localities. Null when none is named. |
| `geo_nearest(lat, lon)` | "Use my current location": the closest locality or district, with its distance, district, canton and province. |
| `geo_distance_km(lat1, lon1, lat2, lon2)` | Haversine distance in kilometres. |
| `geo_places_full` | The table with district, canton and province names resolved, for Provincia / Cantón / Distrito pickers. |

Distance is plain haversine, with no PostGIS: a few thousand places do not need a spatial index. If a product ever needs polygons or road distance, add it then.

## Adding a canton

1. Find the canton's OpenStreetMap relation id (`admin_level` 6): in Overpass, `rel["boundary"="administrative"]["name"="Golfito"];out tags;`.
2. `node tools/load-canton.mjs <relation id> "<Province>" > migrations/00N_seed_<canton>.sql`. It reads the province, canton, districts and the named places inside each district. It needs network access and prints a summary on stderr.
3. Bump the version in `pack.toml`, add a rollback file for the new migration, run `python3 tools/rapscalyon.py test --pack places`, then `catalog`.

Re-running a seed is safe: rows are keyed by `osm_ref`.

## Known limits

- Province and canton coordinates are the centre of the boundary's bounding box, not a population centre. Use them as labels, not as "home".
- Free text can name a common word that is also a place ("Primavera", "Laguna", "Hospital"). Prefer a listing's own location field over its description when both exist.
- Isolated dwellings, farms and islands are not loaded.

## Attribution

Place data is © OpenStreetMap contributors, available under the [ODbL](https://www.openstreetmap.org/copyright). Any page that shows these places must credit OpenStreetMap.
