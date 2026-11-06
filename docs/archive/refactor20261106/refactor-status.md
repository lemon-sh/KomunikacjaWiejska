# Refactor Status — Plan 2

> Companion to [`refactor-plan.md`](refactor-plan.md). Authored 2026-11-06.
> **Status: completed (Phases 0–7 finished).**

## Final verification snapshot

Recorded on 2026-11-06 upon completion of Phase 7:

- **Toolchain:** Xcode 27.2 (27B52), iOS 26.0 deployment target, Swift 6
  language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **Build:** `xcodebuild … build` succeeds with zero compiler warnings.
- **Tests:** 72 tests in 7 focused suites, all passing in `./scripts/verify.sh` on iPhone 17 (iOS 27.2 simulator).
- **Architecture & ADRs:** Reconciled; ADR-0008 (spatial cap) active; flat Zoom 12 cache; 6 km / 12 km thresholds; stubs hermetic with `MockURLProtocol.withHandler` and `InMemoryCameraPersistenceStore`.

## Verification snapshot (baseline)

Recorded on 2026-11-06 before any Plan 2 work:

- **Toolchain:** Xcode 27.2 (27B52), iOS 26.0 deployment target, Swift 6
  language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **Build:** `xcodebuild … build` succeeds. Zero Swift source warnings. The only
  emitted warning is Xcode's "App Intents metadata extraction skipped" note,
  which is unrelated to app code.
- **Tests:** 63 tests in 2 suites, all passing on iPhone 17 (iOS 27.2
  simulator). No test opens a socket (`StubStopsProvider` / `MockURLProtocol`).
- **Size:** 24 Swift files, 4,493 lines. Largest files:
  `ViewModels/MapViewModel.swift` (797), `KomunikacjaWiejskaTests/KomunikacjaWiejskaTests.swift` (1,217).
- **Debug scaffolding:** 23 `#if DEBUG` blocks (15 in `MapViewModel`, 8 in
  `ZbiorkomAPIClient`).
- **Catalog / localization:** 66 cities in `Resources/cities.json`; 51 keys in
  `Localizable.xcstrings`, each with `pl` and `en`.
- **Working tree at baseline:** uncommitted changes on top of `d6dce95` remove
  marker thinning, set thresholds to 6,000 m / 12,000 m, normalise route-badge
  and header-icon sizing, and update the tests to match. The plan treats this
  tree as the baseline.

### Baseline commands

```bash
xcodebuild -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild test -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

## Phase checklist

### Phase 0 — Decisions, guardrails, release blockers

- [x] R0-1 Add a reproducible verification gate (CI + script fix)
- [x] R0-2 Resolve D1 (marker density) and D2 (thresholds) — **blocking**
- [x] R0-3 Assign the app icon and accent colour
- [x] R0-4 Add "implementation differs" banners to stale docs

### Phase 1 — Regressions and user-visible risks

- [x] R1-1 Implement the D1 marker-density strategy
- [x] R1-2 Make launch marker mode intentional (D2)
- [x] R1-3 Remove selection-driven stop recomputation
- [x] R1-4 Batch stop-cache merges
- [x] R1-5 Single source of truth for stop presentation
- [x] R1-6 Fetch only when the visible tile set changes
- [x] R1-7 Meet minimum touch targets
- [x] R1-8 Fix the location double-tap race and add a timeout
- [x] R1-9 Bound per-city error state

### Phase 2 — State machine and decomposition

- [x] R2-1 Replace the stringly-typed load state
- [x] R2-2 Remove `shouldRepositionOnCityChange`
- [x] R2-3 Make the camera state internally consistent
- [x] R2-4 Inject camera persistence
- [x] R2-5 Split `MapViewModel` into focused units
- [x] R2-6 Inject the location source
- [x] R2-7 Centralise constants and identifiers
- [x] R2-8 Adopt one logging policy
- [x] R2-9 Fix view-model ownership and preview hermeticity

### Phase 3 — Views and presentation

- [x] R3-1 Simplify `StopMarkerView`'s dual API
- [x] R3-2 Hide annotation titles natively in compact mode
- [x] R3-3 Finish the design-token pass
- [x] R3-4 Modernise map controls and attribution
- [x] R3-5 Clean up the city picker
- [x] R3-6 Make route-badge text contrast-safe
- [x] R3-7 Finish sheet sizing and accessibility

### Phase 4 — Models and decoding

- [x] R4-1 Clean up `MapTile`
- [x] R4-2 Stop mislabelling stops as buses
- [x] R4-3 De-duplicate positional decoding
- [x] R4-4 Decide the fate of decoded-but-unused data (D3)
- [x] R4-5 Reconcile `RouteType` UI placement with ADR-0004
- [x] R4-6 Make `City` semantics explicit
- [x] R4-7 Remove dead bounding-box plumbing
- [x] R4-8 Normalise access control (D5)
- [x] R4-9 Clean concurrency comments and plan references

### Phase 5 — Networking

- [x] R5-1 Bound and sanity-check the retry policy (D6)
- [x] R5-2 Remove duplication in URL building and decoding
- [x] R5-3 Preserve cancellation semantics

### Phase 6 — Tests

- [x] R6-1 Replace spin-wait synchronization
- [x] R6-2 Isolate defaults and shared state
- [x] R6-3 Split and rename the test target
- [x] R6-4 De-brittle assertions
- [x] R6-5 Simplify the stubs
- [x] R6-6 Add regression tests for this plan

### Phase 7 — Documentation, repo, release

- [x] R7-1 Reconcile all architecture documents
- [x] R7-2 Final verification
- [x] R7-3 Close the plan and move it to `docs/archive/refactor20261106/`

## Open decisions

| ID | Question | Outcome |
|---|---|---|
| D1 | Marker density: deterministic cap vs native clustering vs accept all? | **Representative spatial grid thinning with deterministic cap (250 stops) preserving selected stop (ADR-0008)** |
| D2 | Compact/visibility thresholds: full markers at launch? | **6,000 m compact / 12,000 m visibility thresholds (full markers at launch for all cities)** |
| D3 | Surface entrances from the API, or drop them until the feature exists? | **Surfaced entrances in StopDetailSheet with direct Maps navigation deep-link** |
| D4 | City names: proper nouns only, or English names in `cities.json`? | **Keep native Polish names in `cities.json`; locale-independent city IDs** |
| D5 | Access control: `internal` by default, or keep `public`? | **`internal` by default across target modules** |
| D6 | Retry set: which `URLError` codes? Honour `Retry-After`? | **Bounded 3-attempt exponential backoff for transient errors; immediate fail for `.notConnectedToInternet`** |
| D7 | Location request timeout: 10 s / 15 s / none? | **15-second bounded timeout via `LocationProviding`** |
| D8 | Keep the pass-through `ContentView`? | **Keep `ContentView` as lightweight root coordinator** |

D1 and D2 resolved in Phase 0/1.

## Progress log

- 2026-11-06 — Plan authored from a full codebase review. Baseline build and
  tests verified green. No implementation work started.
- 2026-11-06 — Phase 0 and Phase 1 completed: CI gate, ADR-0008 spatial grid thinning (250 cap), amber accent, touch targets ≥ 44pt, 15s location timeout.
- 2026-11-06 — Phase 2 completed: typed RequestKey/FetchState, selectCity repositioning, atomic camera state, CameraPersistenceStore, MapConstants, LocationProviding.
- 2026-11-06 — Phase 3 completed: StopMarkerView simplified API, native .annotationTitles, DesignTokens wired, modern .alert, zbiorkom.live attribution, route badge contrast.
- 2026-11-06 — Phase 4 completed: clean MapTile (fixed zoom 12), RouteType.unknown handling, TupleReader positional decoding, entrances in StopDetailSheet, RouteType+UI.swift per ADR-0004, City.city(id:) optional, internal-by-default access control.
- 2026-11-06 — Phase 5 completed: bounded retry loop with exponential backoff and jitter, non-retryable notConnectedToInternet, reusable JSONDecoder, CancellationError rethrowing.
- 2026-11-06 — Phase 6 completed: replaced spin-wait synchronization with waitUntil/waitUntilLoaded, isolated persistence state via InMemoryCameraPersistenceStore, split test suite into 7 focused files (all ≤ 370 lines), de-brittled catalog and route tests, simplified StubStopsProvider, added regression tests (72 tests passing).
- 2026-11-06 — Phase 7 completed: reconciled all architecture documents and ADRs, removed stale banners, verified clean gate (0 warnings, 72/72 tests passing), archived Refactor Plan 2.

## Notes for the next agent

- **Read the plan first, not the ADRs.** `docs/architecture.md` §1, ADR-0002,
  ADR-0007, and the `docs/decisions.md` summaries currently describe thinning,
  ancestor-tile reuse, and 25 km/10 km thresholds that the code no longer has.
  R0-4 adds banners; R7-1 rewrites them. Until then, this plan is the source of
  truth for current behaviour.
- **Do not re-add thinning because ADR-0002 says so.** The working tree removed
  it deliberately. D1 decides the replacement (cap, native clustering, or an
  explicit unbounded policy with measurement).
- **The tile cache is flat Zoom 12.** There is no ancestor hierarchy; a tile is
  covered only if it is in `fetchedTiles`. The comments claiming descendant
  coverage (`MapViewModel` around the `fetchedTiles` declaration) are stale.
- **`MapViewModel` is the hot spot.** Prefer behaviour-preserving extractions
  (`StopCache`, `ViewportLoadPlanner`, `CameraPersistence`) over rewriting the
  fetch path in one commit.
- **Tests are green but not isolated.** The persistence test mutates
  `UserDefaults.standard` while the suite runs in parallel. Fix the injection
  (R2-4) before adding more tests that touch defaults.
- **Keep user-facing copy in `Localizable.xcstrings`.** Any new error, alert,
  or control label needs `pl` and `en` entries in the same commit.
- **Native-first remains mandatory.** If D1 chooses clustering, use MapKit's
  native clustering; do not build a custom clustering engine or custom map
  chrome.
- **When complete:** update this file, mark every checkbox, record the final
  build/test snapshot and manual QA results, then move the directory to
  `docs/archive/refactor20261106/` and update
  `docs/archive/README.md`, `README.md`, and `AGENTS.md`.
