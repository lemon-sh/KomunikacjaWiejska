# ADR-0001 — Stops fetch strategy: viewport bbox (Decision D1)

**Status:** Accepted (2026-11-05)

## Context
Stops can be fetched for an entire city (`{city}/stops`) or for the visible viewport
(`{city}/stops?bbox=minLon,minLat,maxLon,maxLat`). Metropolitan networks (Warsaw, GZM)
contain tens of thousands of stop poles; the mobile client must not download and bind
all of them at once.

## Decision
Option **A — viewport bbox fetch**, as recorded in `docs/refactor-plan.md` §11:

- Fetches are triggered by `.onMapCameraChange(frequency: .onEnd)` and debounced
  350 ms in `MapViewModel`.
- The visible `MKCoordinateRegion` is converted by `BoundingBox` to the API's
  `bbox` query parameter (`minLon,minLat,maxLon,maxLat`).
- Results are cached per viewport key (`city` + the exact six-decimal `bbox`
  sent to the API) with a 10-minute TTL, LRU-capped at 8 entries. Empty or
  failing responses are never cached.
- A refresh keeps the previously displayed stops on screen; a new viewport
  (pan/zoom/city switch) clears the old data first.

Rejected: Option B (full-city fetch) — unbounded memory/latency on large networks.

## Consequences
- Request pattern must match `docs/architecture.md` §1.
- `BoundingBox` is production-wired (previously dead code).
- Zooming out does not merge previously fetched viewports; the viewport cache
  covers repeated round-trips instead.
