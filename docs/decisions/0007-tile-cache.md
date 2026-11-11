# ADR-0007 — Session tile cache for stops

**Status:** Superseded by [ADR-0009](0009-api6-sse-streaming.md) (2026-11-11) — originally accepted 2026-11-05, updated 2026-11-06

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
Use a **session-only, per-city tile cache with a flat Zoom 12 grid**:

- Cache stops in one `cachedStopsByID` dictionary per selected city. New
  responses overwrite entries by stop ID (newest wins).
- Record successful coverage in a `fetchedTiles` set of Web Mercator
  Zoom 12 tiles (`MapTile.zoom = 12`, ~6 km × 6 km per tile).
- All coverage tiles share the same coarseness without hierarchy or ancestor
  traversal. A required tile is covered if it is directly contained in `fetchedTiles`.
- Distance thresholds for stops:
  - `stopCompactDistanceThreshold = 6_000` metres: stops display as compact dot markers with hidden annotation titles.
  - `stopVisibilityDistanceThreshold = 12_000` metres: when camera distance exceeds 12,000 m, stop markers are hidden (`stops = []`) and network fetches are suppressed. Zooming back in restores fetching and rendering.
- On camera settle within visible range, compute the visible Zoom 12 tiles.
  If all are covered, make no request. Otherwise request the **union bbox of the missing tiles**
  as one request and mark them fetched on success.
- Render from the city-wide stop dictionary, filtering to the current viewport
  before applying representative spatial grid thinning (capping at 250 stops per ADR-0008).
- Keep existing markers on screen while new tiles load; a failed request leaves
  the cache untouched.
- Treat a successful empty response as valid coverage so it is not retried on
  every settle.
- Clear both the stop dictionary and the tile set on every city switch.
- On background transition (`scenePhase == .background`), the camera center
  coordinates and zoom distance are persisted via `CameraPersistenceStore` and restored
  on next launch if valid for the selected city (or unconditionally for PKP).
- The stop cache itself is never persisted to non-volatile storage.
- Entries do not expire while the app process lives.

## Consequences
- Panning inside fetched coverage is free and no longer blanks the map.
- Returning to any covered viewport, including a slightly different one,
  reuses the cached stops.
- Simpler flat tile grid eliminating multi-level tile cache hierarchies and parent traversal.
- Memory is unbounded for the session but bounded in practice by the selected
  city’s unique stops plus a small set of tile keys.
- Server-side changes are not picked up until city switch or relaunch.
- A requested bbox may include already-cached tiles; merging by stop ID makes
  the duplicate stops harmless.
- Antimeridian and pole handling is best-effort; the app only ships Polish
  networks.

Rejected: reverting to a coarse shared bbox key (omits high-zoom stops), and a
TTL/LRU cache keyed by exact viewport (near-zero hit rate while panning).
