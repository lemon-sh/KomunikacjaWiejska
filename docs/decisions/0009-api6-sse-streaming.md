# ADR-0009 — `/api6` SSE Streaming & Viewport Architecture

**Status:** Accepted (2026-11-11)  
**Supersedes:** [ADR-0001](0001-fetch-strategy.md), [ADR-0007](0007-tile-cache.md), [ADR-0008](0008-marker-density.md)

## Context

A live transit map across metropolitan networks (such as Warsaw or Upper Silesia) must balance marker density, fresh vehicle telemetry, low bandwidth, and detailed inspection views without relying on client-side polling heuristics or heavy spatial caching:
- Rendering full stop and vehicle annotations across city-wide viewports causes main-thread frame drops, while arbitrary client-side spatial caps hide live density cues when zoomed out.
- Vehicle and stop sheets need live pushed departure boards, full trip itineraries (completed + upcoming stops), `1e6` encoded route polylines, `percentTraveled` progress, per-stop arrival/departure timestamps, status flags (`Scheduled` / `OnTrip` / `Cancelled`), alerts, and fleet metadata.

`zbiorkom.live` provides these capabilities natively via compact positional JSON tuples streamed over Server-Sent Events (`EventSource`) at `https://api.zbiorkom.live/api6`.

## Decision

Standardize **KomunikacjaWiejska** on `https://api.zbiorkom.live/api6` using native Apple networking and Swift 6 concurrency:

1. **Native Byte-Level SSE Client (`ZbiorkomAPIClient` + `SSEFrameParser`):**
   - Implement a pure Apple `URLSession.bytes(for:)` byte-level SSE frame parser (preserving blank `\n\n` event boundaries that Foundation `AsyncBytes.lines` skips) emitting `AsyncThrowingStream` events with automatic reconnect (`5` retries, `2s` default or `retry:` hint) and foreground/background lifecycle handling (`45s` background disconnect, `10s` stale refresh on foreground resume).
   - Strictly percent-encode each URL path segment (`alphanumerics + "-._~"`) so IDs containing `:` (e.g. `3:MM831`) encode as `3%3AMM831`, matching browser `encodeURIComponent`.
2. **Zoom-Driven Viewport Streaming (`mapFeatures/{zoom}/{bbox}/stream`):**
   - Drive map marker density directly from server-controlled zoom streams without client tile caches, polling timers, or client-side vehicle caps.
   - Derive Web Mercator zoom from camera longitude span and viewport width; render server-emitted `dots` (`DotMarkerView`) when zoomed out and full 7-tuple stops + 6-tuple positions when zoomed in.
3. **Selection Isolation, Navigation Stack & Detail Sheets:**
   - Selecting a stop opens `stops/{stop.city}/stops/{stopId}/stream` (using the entity's own `city` for cross-city operators like `mld` and `pkp`), hydrates full 10-tuple metadata (`direction`, `routes`, `entrances`), isolates map markers to the stop, exits, and active departure vehicles, and streams live departures.
   - Tapping any live or scheduled departure transitions inside the active sheet container to `VehicleDetailSheet` (via `positions/{vehicleId}/stream` or `trips/{tripId}/stream` plus optional `vehicles/vehicle/{id}` fleet metadata) with a `<` Back stack returning to `StopDetailSheet`, draws the `1e6` Google-encoded `MapPolyline` and itinerary stop dots, isolates unrelated map features, supports a camera vehicle-follow toggle, and displays full trip timelines with `sequence` past-stop dimming, `percentTraveled` track indicator, per-stop arrival/departure times in the city's `TimeZone`, status/platform/track/on-demand/drop-off badges, and alerts.
4. **Dynamic City Catalog (`GET /api6`):**
   - Fetch cities dynamically from `GET /api6` on startup with no bundled offline catalog (entering a retryable error state if offline before opening viewport SSE), excluding `virtual: true` meta-networks from `CityPickerSheet` and city-switch suggestions.

## Alternatives Rejected

- **Adding third-party SSE / polyline libraries (e.g. `LDSwiftEventSource`, `Polyline`):** Rejected to preserve the zero third-party dependency constraint (`AGENTS.md`).
- **Maintaining a client-side tile cache or spatial grid cap on top of `/api6`:** Rejected because `mapFeatures/{zoom}/{bbox}/stream` already manages payload density by server zoom tier (`dots` vs full `positions` + 7-tuple `stops`).

## Consequences

- Real-time ~10s SSE pushes keep positions, stop departures, and trip delays synchronized without timer polling.
- `ADR-0001` (REST bbox polling), `ADR-0007` (Zoom 12 tile cache), and `ADR-0008` (250-stop client cap) are superseded by server-driven SSE viewport streaming.
- Model decoders handle variable-length tuples (`Stop` 7 vs 10 elements; `VehiclePosition` 6 vs 9 elements; `TripStopUpdate` 2..5 elements) and tolerate unknown trailing fields cleanly.
