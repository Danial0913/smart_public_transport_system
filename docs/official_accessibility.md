# Official accessibility records

The accessibility screens use official facility information rather than local
user reports. Existing locally stored reports are preserved but do not determine
facility values or appear in the station screens.

## Sources and coverage

- Government transit snapshots: https://developer.data.gov.my/realtime-api/gtfs-static
  The existing converter reads `wheelchair_boarding`. All 15 bundled snapshots
  checked on 2026-09-05 have no known boarding values. Unknown is not a confirmed
  accessible or inaccessible stop. Boarding does not certify a step-free route.
- MRT Corp station pages: https://www.mymrt.com.my/projects/kajang-line/stations/
  The supplementary snapshot covers 65 MRT stop IDs in the current rail feed
  (including separate line IDs for shared stations). Only explicitly documented
  lifts and disabled-friendly toilets are imported. Each record includes its
  station page, checked date, and supporting facility label.

Station pages describing ramps or lifts do not establish an entire step-free
route or confirm wheelchair boarding. Missing fields remain unknown. Facility
presence does not confirm live operating status. The previous reported-lift-outage
switch is therefore no longer shown.

Records match exact feed stop IDs. MRT data is not applied to nearby bus stops or
LRT stations with the same name. Results, details, and comparisons show only
available facilities. A stop with none of the four available facilities is excluded.
Every explicitly selected search facility must be available; without a selection,
at least one facility must be available. Saved accessibility needs do not add
hidden search requirements. The separate confirmed-accessible checkbox has been
removed because official availability is now mandatory for every result.

The current snapshot returns 64 distinct MRT stops for a Klang Valley lift or
accessible-toilet search (the repository merges the duplicate Kwasa Damansara
line IDs). Wheelchair and step-free filters return no matches until
official sources confirm those fields. A region with no documented available
facilities also returns no matches; missing evidence is never treated as available.

## Refreshing the supplementary snapshot

From the repository root, run `python tool/refresh_official_accessibility.py`,
review changes to `assets/data/official_accessibility.json`, and run `flutter test`.
The importer checks station-specific source links and uses explicit spelling
aliases. It caches downloaded pages under `build/official_accessibility` for the
same UTC day so interrupted runs can resume without downloading every page again.
Failed parsing stops the import before replacing the existing snapshot.

The app reads the bundled snapshot offline; pull-to-refresh reloads the result
view, not the live MRT website. Updated records must be bundled in a new build.
