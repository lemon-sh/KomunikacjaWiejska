# ADR-0007 — Session tile cache for stops

**Status:** Accepted (2026-11-05)

## Context
The stops endpoint returns every stop inside a bbox, independent of zoom. The
previous cache was keyed by the exact six-decimal viewport with a 10-minute TTL
and an 8-entry LRU. Panning away and back almost never reproduced the same
four bbox numbers, so the cache missed, cleared the markers, and refetched a
region that largely overlapped data already downloaded.

Stop data changes very rarely during an app session. A single user is also
unlikely to visit enough distinct stop poles in one city for unbounded memory
to be a practical concern.

## Decision
Use a **session-only, per-city tile cache**:

- Cache stops in one `cachedStopsByID` dictionary per selected city. New
  responses overwrite entries by stop ID (newest wins).
- Record successful coverage in a `fetchedTiles` set of Web Mercator
  (`z/x/y`) tiles.
- Choose the zoom level so the viewport spans about three tiles. This keeps a
  request local without producing a large tile fan-out.
- A required tile is covered if it or any **ancestor** tile has been fetched.
  A coarser bbox is a superset of every descendant, so zooming in needs no new
  data.
- On a camera settle, compute the visible tiles. If all are covered, make no
  request. Otherwise request the **union bbox of the missing tiles** as one
  request and mark them fetched on success.
- Render from the city-wide stop dictionary, always filtering to the current
  viewport before applying the 250-marker thinning pass.
- Keep existing markers on screen while new tiles load; a failed request leaves
  the cache untouched.
- Treat a successful empty response as valid coverage so it is not retried on
  every settle.
- Clear both the stop dictionary and the tile set on every city switch.
- Never persist the cache to `UserDefaults`, files, or any other non-volatile
  storage. Only `lastSelectedCityId` remains persisted.
- Entries do not expire while the app process lives.

## Consequences
- Panning inside fetched coverage is free and no longer blanks the map.
- Returning to any covered viewport, including a slightly different one,
  reuses the cached stops.
- Zooming out of a deeply zoomed area may fetch coarser tiles once; zooming
  back in is then served by ancestor coverage.
- Memory is unbounded for the session but bounded in practice by the selected
  city’s unique stops plus a small set of tile keys.
- Server-side changes are not picked up until city switch or relaunch.
- A requested bbox may include already-cached tiles; merging by stop ID makes
  the duplicate stops harmless.
- Antimeridian and pole handling is best-effort; the app only ships Polish
  networks.

Rejected: reverting to a coarse shared bbox key (omits high-zoom stops), and a
TTL/LRU cache keyed by exact viewport (near-zero hit rate while panning).
