# Places
> A place directory for Costa Rica (Provincia, Cantón, Distrito, town) with distance and "where is this?" lookups built in.

## Who it's for
Builders of listing, delivery or matching products who need to rank by distance, let people pick where they live, or turn "placed in Sabalito" into coordinates.

## What you get
- Provincia, Cantón, Distrito and town records from OpenStreetMap, ready to load for any canton.
- Typo- and accent-tolerant search, nearest-place lookup from a GPS point, and the place named inside free text.
- Straight-line distance in kilometres, with no map service and no per-lookup cost.

## Works well with
items-matching-ranking, real-estate-listings, item-search.

## Under the hood
Plain tables and SQL functions: a trigram index for fuzzy names, haversine for distance. Read-only reference data behind row-level security and the MFA gate. Place data © OpenStreetMap contributors (ODbL).
