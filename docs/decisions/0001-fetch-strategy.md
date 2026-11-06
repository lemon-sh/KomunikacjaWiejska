# ADR-0001 — Stops fetch strategy: viewport bbox (Decision 1D1)

**Status:** Accepted (2026-11-05)

## Context
Stops can be fetched for an entire city (`{city}/stops`) or for the visible viewport
(`{city}/stops?bbox=minLon,minLat,maxLon,maxLat`). Metropolitan networks (Warsaw, GZM)
contain tens of thousands of stop poles; the mobile client must not download and bind
all of them at once.

## Decision
Option **A — viewport bbox fetch**, as recorded in `docs/archive/refactor20261105/refactor-plan.md` §11:

- Fetches are triggered by `.onMapCameraChange(frequency: .onEnd)` and debounced
  350 ms in `MapViewModel`.
- The visible `MKCoordinateRegion` is converted by `BoundingBox` to the API's
  `bbox` query parameter (`minLon,minLat,maxLon,maxLat`).
- Results are cached per city in a session-only tile cache: fetched stops are
  merged by ID, and successful tile coverage is recorded so overlapping
  viewports reuse it. Failed requests are not cached, and the cache is cleared
  on city switch. See [ADR-0007](0007-tile-cache.md).
- Existing markers stay on screen while additional tiles load; rendering is
  always filtered to the current viewport.

Rejected: Option B (full-city fetch) — unbounded memory/latency on large networks.

## Consequences
- Request pattern must match `docs/architecture.md` §1.
- `BoundingBox` is production-wired (previously dead code).
- The tile cache covers overlapping pans and repeated round-trips; zooming out
  fetches coarser tiles once so later zoom-ins can reuse them.
