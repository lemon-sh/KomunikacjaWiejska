# Refactor Status

> Companion to [`refactor-plan.md`](refactor-plan.md). Updated 2026-11-05.
> **Status: all phases complete.** The plan is retained as a historical record.

## Verification snapshot

- `xcodebuild build` — app + tests build in **Swift 6 language mode** with no
  source warnings (the only build warning is Xcode's App Intents metadata note,
  which is unrelated to app code).
- `xcodebuild test` — **40 tests in 2 suites, all passing** on iPhone 17 /
  iOS 27.2 with `IPHONEOS_DEPLOYMENT_TARGET = 26.0`.
- Tests are **hermetic**: all `MapViewModel` tests inject `StubStopsProvider`;
  `ZbiorkomAPIClient` tests use `MockURLProtocol`. No test opens a socket.
- `rg "isZoomedOutForStops|maxSpanForStops|selectStop"` in Swift sources returns
  nothing.
- `scripts/check-toolchain.sh` reports Xcode 27.2 OK; the shared scheme is
  committed and `xcuserdata` is untracked.

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

### Phase 2 — Performance & data lifecycle (D1-A, D2-A)
- **P2-1** Viewport `bbox` fetch on camera end with 350 ms debounce;
  `BoundingBox` wired end-to-end; docs updated.
- **P2-2** Grid-based thinning bounds rendering to 250 markers, deterministic.
  The grid is cap-driven (15×16 = 240 slots), not derived from the stop count;
  a stop-count-derived grid collapsed dense viewports to a few markers.
- **P2-3** Viewport cache with 10-minute TTL and 8-entry LRU; failures and
  empty/partial results are never cached; explicit refresh API.
- **P2-4** Camera metrics grouped into one `CameraState` with epsilon equality;
  markers re-render only when the thinned set changes.
- **P2-5** Backgrounding cancels fetches and stops location updates; returning
  to `.active` reloads the current viewport.
- ADRs: `docs/decisions/0001-fetch-strategy.md`, `0002-marker-density.md`.

### Phase 3 — API & model robustness
- **P3-1** No force unwrap in the client; `URLComponents` built once; dedicated
  `invalidResponse`/`transport`/`serverError` cases; localized Polish/English
  messages; DEBUG decoding details logged via `os.Logger`; `Accept` header;
  documented 15 s timeout; one jittered retry for transient errors/5xx, never
  4xx. Covered by `MockURLProtocol` tests.
- **P3-2** `StopsResponse` isolation attribute documented with the exact
  diagnostic and removal condition; it remains the deliberate `nonisolated`
  decoding entry point under Swift 6.
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

### Phase 4 — UI, UX, accessibility
- **P4-1** `Localizable.xcstrings` with Polish and English; `MapMode` has a
  localized `displayName` while `rawValue` stays a stable identifier; no literal
  UI copy remains in views; `RouteType` display names moved to
  `RouteType+UI.swift`.
- **P4-2** The fixed 52 pt spacer is gone; top chrome is a safe-area-aware
  stack; shared metrics live in `DesignTokens`; markers scale with Dynamic Type
  up to a documented cap; the detail sheet is scrollable and offers `.large`
  for accessibility sizes.
- **P4-3** Icon-only controls have labels/values/hints; markers and route badges
  are single accessibility elements; selected state is exposed with traits.
- **P4-4** Single `MapControlsComboView` initializer, injected
  `LocationManager`, no singleton fallback; grouped glass controls use
  `glassEffect`/`glassEffectUnion` with an explanatory comment (native
  `GlassEffectContainer`); hand-drawn thumbnails replaced by simple native icon
  cards.
- **P4-5** The status capsule distinguishes initial load / refresh / city
  switch, shows a two-line localized error with an inline retry button, and the
  top chrome includes a visible refresh control. Last successful data stays
  visible during same-viewport refresh.

### Phase 5 — Project hygiene, concurrency, docs
- **P5-1** `xcuserdata` untracked; `.gitignore` covers user data and local build
  artifacts; shared scheme committed under `xcshareddata`.
- **P5-2** `README.md` documents Xcode 27.2+ and the JSON project format;
  `scripts/check-toolchain.sh` fails loudly on older toolchains.
- **P5-3** `SWIFT_VERSION = 6.0`; strict concurrency; value types that cross
  actors are `nonisolated` with comments; test doubles use documented
  lock-guarded `@unchecked Sendable` only where access is protected.
- **P5-4** `IPHONEOS_DEPLOYMENT_TARGET = 26.0` for app and tests (D6 applied).
- **P5-5** Architecture/API/cities/AGENTS docs reconciled with the code; ADRs
  0003–0006 added.

### Post-completion follow-up — location one-shot flow
- **P1-7 follow-up** The location button now awaits the permission decision and
  the one-shot fix as a single async operation, so the camera centers when the
  fix arrives (including after a first-time permission grant). Fix failures
  show a localized "Location unavailable" alert; denial still deep-links to
  Settings. The write-only `locationAccessDenied` flag was removed and
  `LocationAuthorizationState.resolve` is covered by a hermetic test.
- Additional copy: `location.error.title`, `location.error.message`,
  `location.error.ok` (Polish and English).
- **P2-3 follow-up** The rendered marker array is compared by full `Stop`
  value instead of ID only, so a manual refresh that returns new bearings,
  routes, or names for the same stops is applied (regression test added).
- **P2-3 follow-up** Viewport cache keys now use the exact six-decimal `bbox`
  sent to the API instead of a 0.01° grid, which could serve one viewport's
  snapshot to a different nearby viewport and omit stops at high zoom
  (regression test added). ADR-0001 updated.

## Residual manual QA

Automated verification is complete. The following are release checks rather than
open refactor work:

- VoiceOver + Increase Contrast on a device.
- Dynamic Type XXL on a notched and non-notched device, portrait/landscape.
- Perceived performance panning Warsaw/GZM on hardware.
- Airplane-mode launch, city switch, and retry recovery.
- An iOS 26 runtime smoke test (current simulator is iOS 27.2).

## Notes for the next agent
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` remains intentional; mark new pure
  value types that cross actors as `nonisolated` with a reason.
- `MapViewModel` caches **per viewport**, not per city. When changing fetch
  behaviour, update `docs/architecture.md` §1 and ADR-0001 in the same commit.
- The API client retry doubles as the test of jittered backoff; keep 4xx
  non-retryable.
- User-facing copy belongs in `Resources/Localizable.xcstrings`; identifiers
  stay locale-independent.
