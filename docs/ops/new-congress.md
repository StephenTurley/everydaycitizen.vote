# A new Congress

A congress sits from Jan 3 of an odd year (the 120th from Jan 3, 2027). The
switch is automatic (`Federal.Congresses`); these are the parts that need a
person. See DECISIONS, 2026-11-04.

## Once, after the deploy that added district maps

- Run `zip_districts` so the existing ZIP rows record their map; until then
  ZIP lookups ask for the full address:
  `fly ssh console -C "/app/bin/everyday_citizen rpc 'EverydayCitizen.Release.ingest(\"zip_districts\")'"`

## Before each Jan 3

- Check `census_vintages` in `config/config.exs` has the next congress. The
  geocoder lists each vintage's district layer:
  `https://geocoding.geo.census.gov/geocoder/vintages?benchmark=Public_AR_Current&format=json`,
  then query a point with `vintage=<name>` and look for
  "<nth> Congressional Districts". Without an entry, address lookup is
  unavailable from Jan 3.

## When Census publishes the new ZIP file (months after Jan 3)

- The file is `tab20_cd<NNN>20_zcta520_natl.txt` under
  `https://www2.census.gov/geo/docs/maps-data/data/rel2020/cd-sld/`.
- Add it to `zip_files` in `config/config.exs`, deploy, and run `zip_districts`.
  Until then ZIP lookups ask for the street address.

## On and after Jan 3

- `sync_congress` tries again every 30 minutes while Congress.gov does not
  list the new congress; the other jobs wait up to a day for its session. Check `fly logs` that it
  ran, and the coverage report the next morning.
- Visitors and accounts with a saved district see "District lines have changed
  since you last looked up your address" once, and look it up again.
- Bills of the previous congress keep syncing for 30 days.
