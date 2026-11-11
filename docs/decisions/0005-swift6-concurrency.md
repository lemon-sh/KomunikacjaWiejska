# ADR-0005 — Swift 6 language mode and isolation model

**Status:** Accepted (2026-11-05) — implemented in 1P5-3

## Context
The project already used `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` but stayed
in Swift 5 mode. That made cross-actor model use a warning today and an error
under Swift 6. The app is small enough to adopt the strict model properly rather
than suppress diagnostics.

## Decision
Enable **Swift 6 language mode** with complete strict concurrency. Keep
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so UI types stay main-actor by
default. Value types that must cross actor boundaries are explicitly
`nonisolated`, with a comment:

- `BoundingBox`, `TransitDataProviding`, `TupleReader`, `PolylineDecoder`, `SSEFrameParser`, and DTO models (`CitiesResponse`, `City`, `Stop`, `VehiclePosition`, `DotVehicle`, `TripModels`).
- The `Sendable` model values (`City`, `Stop`, `StopRoute`, `StopEntrance`,
  `RouteType`) compile cleanly under the same settings; they are pure value
  types and need no actor hop.
- `ZbiorkomAPIClient` remains an independent actor.
- `LocationManager` stays `@MainActor` and conforms to
  `CLLocationManagerDelegate` directly; no isolation escape hatch is needed with
  the current SDK.

No `@preconcurrency` is used.

## Consequences
- Model decoding can run off the main actor without data races.
- New cross-actor types must be `Sendable`/`nonisolated` deliberately.
- Test doubles use lock-guarded `@unchecked Sendable` only where access is
  actually protected by `OSAllocatedUnfairLock`, with a comment.
