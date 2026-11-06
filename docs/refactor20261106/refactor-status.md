# Refactor Status — Plan 2

> Companion to [`refactor-plan.md`](refactor-plan.md). Authored 2026-11-06.
> **Status: plan authored, not started.** Update this file as phases land; do
> not mark a task complete until its acceptance criteria pass.

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

- [ ] R0-1 Add a reproducible verification gate (CI + script fix)
- [ ] R0-2 Resolve D1 (marker density) and D2 (thresholds) — **blocking**
- [ ] R0-3 Assign the app icon and accent colour
- [ ] R0-4 Add "implementation differs" banners to stale docs

### Phase 1 — Regressions and user-visible risks

- [ ] R1-1 Implement the D1 marker-density strategy
- [ ] R1-2 Make launch marker mode intentional (D2)
- [ ] R1-3 Remove selection-driven stop recomputation
- [ ] R1-4 Batch stop-cache merges
- [ ] R1-5 Single source of truth for stop presentation
- [ ] R1-6 Fetch only when the visible tile set changes
- [ ] R1-7 Meet minimum touch targets
- [ ] R1-8 Fix the location double-tap race and add a timeout
- [ ] R1-9 Bound per-city error state

### Phase 2 — State machine and decomposition

- [ ] R2-1 Replace the stringly-typed load state
- [ ] R2-2 Remove `shouldRepositionOnCityChange`
- [ ] R2-3 Make the camera state internally consistent
- [ ] R2-4 Inject camera persistence
- [ ] R2-5 Split `MapViewModel` into focused units
- [ ] R2-6 Inject the location source
- [ ] R2-7 Centralise constants and identifiers
- [ ] R2-8 Adopt one logging policy
- [ ] R2-9 Fix view-model ownership and preview hermeticity

### Phase 3 — Views and presentation

- [ ] R3-1 Simplify `StopMarkerView`'s dual API
- [ ] R3-2 Hide annotation titles natively in compact mode
- [ ] R3-3 Finish the design-token pass
- [ ] R3-4 Modernise map controls and attribution
- [ ] R3-5 Clean up the city picker
- [ ] R3-6 Make route-badge text contrast-safe
- [ ] R3-7 Finish sheet sizing and accessibility

### Phase 4 — Models and decoding

- [ ] R4-1 Clean up `MapTile`
- [ ] R4-2 Stop mislabelling stops as buses
- [ ] R4-3 De-duplicate positional decoding
- [ ] R4-4 Decide the fate of decoded-but-unused data (D3)
- [ ] R4-5 Reconcile `RouteType` UI placement with ADR-0004
- [ ] R4-6 Make `City` semantics explicit
- [ ] R4-7 Remove dead bounding-box plumbing
- [ ] R4-8 Normalise access control (D5)
- [ ] R4-9 Clean concurrency comments and plan references

### Phase 5 — Networking

- [ ] R5-1 Bound and sanity-check the retry policy (D6)
- [ ] R5-2 Remove duplication in URL building and decoding
- [ ] R5-3 Preserve cancellation semantics

### Phase 6 — Tests

- [ ] R6-1 Replace spin-wait synchronization
- [ ] R6-2 Isolate defaults and shared state
- [ ] R6-3 Split and rename the test target
- [ ] R6-4 De-brittle assertions
- [ ] R6-5 Simplify the stubs
- [ ] R6-6 Add regression tests for this plan

### Phase 7 — Documentation, repo, release

- [ ] R7-1 Reconcile all architecture documents
- [ ] R7-2 Final verification
- [ ] R7-3 Close the plan and move it to `docs/archive/refactor20261106/`

## Open decisions

| ID | Question | Outcome |
|---|---|---|
| D1 | Marker density: deterministic cap vs native clustering vs accept all? | **pending** |
| D2 | Compact/visibility thresholds: full markers at launch? | **pending** |
| D3 | Surface entrances from the API, or drop them until the feature exists? | **pending** |
| D4 | City names: proper nouns only, or English names in `cities.json`? | **pending** |
| D5 | Access control: `internal` by default, or keep `public`? | **pending** |
| D6 | Retry set: which `URLError` codes? Honour `Retry-After`? | **pending** |
| D7 | Location request timeout: 10 s / 15 s / none? | **pending** |
| D8 | Keep the pass-through `ContentView`? | **pending** |

D1 and D2 block Phase 1. Do not start marker work before they are answered.

## Progress log

- 2026-11-06 — Plan authored from a full codebase review. Baseline build and
  tests verified green. No implementation work started.

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
