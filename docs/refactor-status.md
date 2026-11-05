# Refactor Status

> Companion to [`refactor-plan.md`](refactor-plan.md). Updated 2026-11-05.

## Verification snapshot

- `xcodebuild build` — app + tests build with **zero warnings** (project warning
  state unchanged from baseline).
- `xcodebuild test` — **33 tests in 2 suites, all passing**.
- Tests are **hermetic**: all `MapViewModel` tests inject `StubStopsProvider`;
  `ZbiorkomAPIClient` tests use `MockURLProtocol`. No test opens a socket.
- `rg "isZoomedOutForStops|maxSpanForStops|selectStop"` in Swift sources returns
  nothing.

## Completed

### Phase 0 — Test harness safety
- **P0-1** Injectable `StopsProviding` protocol; `ZbiorkomAPIClient` conforms;
  `MapViewModel` accepts `any StopsProviding`.
- **P0-2** No I/O in `MapViewModel.init`; stops load from a single `.task`;
  `deinit` cancels in-flight work; idempotent state machine.
- **P0-3** Hermetic tests plus coverage for malformed tuples, unknown route
  types, null bearing, empty collections, bbox queries, compact thresholds,
  cache hits, in-flight city switches, and API error mapping.

### Phase 1 — Correctness
- **P1-1** Duplicate fetch removed; single load entry point.
- **P1-2** Switching city clears the old markers immediately; generation token
  discards stale responses; loading/errors are tracked per city.
- **P1-3** Compact marker mode is derived from camera **distance** (50 km), not
  latitude span; all normal cities launch with full markers.
- **P1-4** Removed `isZoomedOutForStops`, `maxSpanForStops`, `selectStop`;
  `BoundingBox` is now production-wired instead of dead.
- **P1-5** Selection is a single `selectedStopID` source of truth using
  `.tag(stop.id)`; the sheet is derived from it.
- **P1-6** Bearing notch rotates around the badge centre.
- **P1-7** Denied/disabled location shows an explanatory alert with an "Open
  Settings" deep link; one-shot `requestLocation()` instead of a perpetual
  update loop; `didFailWithError` logs.

### Phase 2 — Performance & data lifecycle (D1-A, D2-A, D6)
- **P2-1** Viewport `bbox` fetch on camera end with 350 ms debounce;
  `BoundingBox` wired end-to-end; docs updated.
- **P2-2** Grid-based thinning bounds rendering to 250 markers, deterministic.
- **P2-3** Viewport cache with 10-minute TTL and 8-entry LRU; failures and
  empty/partial results are never cached; explicit refresh API.
- **P2-4** Camera metrics grouped into one `CameraState` with epsilon equality;
  markers re-render only when the thinned set changes.
- **P2-5** Backgrounding cancels fetches and stops location updates; returning
  to `.active` reloads the current viewport.
- ADRs: `docs/decisions/0001-fetch-strategy.md`, `0002-marker-density.md`,
  `0003-deployment-target.md`.

### Phase 3 — API & model robustness
- **P3-1** No force unwrap in the client; `URLComponents` built once; dedicated
  `invalidResponse`/`transport`/`serverError` cases; honest Polish messages;
  DEBUG decoding details; `Accept` header; documented 15 s timeout; one jittered
  retry for transient errors/5xx, never 4xx. Covered by `MockURLProtocol` tests.
- **P3-2** `StopsResponse` isolation attribute documented with the exact
  diagnostic and removal condition (P5-3).
- **P3-3** Positional tuple decoders validate element counts and coordinate
  ranges, decode with type/field/index diagnostics, normalize bearings, and
  tolerate extra trailing elements.
- **P3-4** Entrance IDs are `"{stopID}-entrance-{index}"` — deterministic,
  duplicate-safe; ordering documented as part of identity.
- **P3-5** `Color(hex:)` is failable, validates lengths/chars, documents ARGB,
  and all call sites pass explicit fallbacks; covered by tests.
- **P3-6** `RouteType` no longer imports CoreLocation, exposes
  `displayableCases`, and gives `.unknown` a distinct neutral symbol/color.
- **P3-7** City catalog moved to `KomunikacjaWiejska/Resources/cities.json`
  (all 66 documented networks), `aliases` supported in picker search,
  `docs/cities.md` reconciled with the bundle.

## Remaining work

### Phase 4 — UI, UX, accessibility (not started)
- **P4-1** Localizable string catalog, `MapMode.displayName`, pl/en locale.
  (D3 still open: Polish only vs Polish + English.)
- **P4-2** Safe-area-aware layout instead of the fixed 52 pt spacer; Dynamic
  Type audit; design tokens.
- **P4-3** Accessibility labels/hints, combined marker elements, `.isSelected`.
- **P4-4** Mostly done: the redundant `init(viewModel:)` singleton fallback was
  removed with P1-7. Still open: unify glass styling and decide the fate of the
  hand-drawn map thumbnails.
- **P4-5** Actionable error capsule with retry, distinct loading states,
  offline-friendly copy that doesn't cover controls.
  (D4 resolved as TTL + manual refresh; a visible refresh control is still to
  add with P4-5.)

### Phase 5 — Project hygiene, concurrency, docs (not started)
- **P5-1** Untrack `xcuserdata`, verify ignores, commit a shared scheme.
- **P5-2** Document minimum Xcode for the JSON project format + CI guard.
- **P5-3** Swift 6 language mode + strict concurrency; remove/justify the
  `nonisolated` attributes.
- **P5-4** Apply **D6**: lower `IPHONEOS_DEPLOYMENT_TARGET` from 27.2 to 26.0
  (decision accepted, setting not yet changed) and build on the lowest runtime.
- **P5-5** Remaining doc reconciliation after Phase 4/5 (glass idiom wording,
  AGENTS.md file map, ADRs already added).

### Open decisions
- **D3** localization scope — decide in P4-1.
- **D5** entrance identity — resolved in P3-4 as tuple index (deterministic).
- **D4** cache freshness — resolved in P2-3 as TTL + manual refresh API.

## Notes for the next agent
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` changes concurrency rules
  materially; prefer explicit `nonisolated` on cross-actor value types and
  document any escape hatch, as done for `StopsProviding`, `BoundingBox`, and
  `StopsResponse`.
- `MapViewModel` now caches **per viewport**, not per city. When changing fetch
  behaviour, update `docs/architecture.md` §1 and ADR-0001 in the same commit.
- The API client retry doubles as the test of jittered backoff; keep 4xx
  non-retryable.
