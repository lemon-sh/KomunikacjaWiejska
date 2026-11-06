# Refactor Plan 2 — Post-Refactor Hardening

> **Status: not started (2026-11-06).** This is the active backlog for the second
> code-quality pass. When every phase is complete, update
> [`refactor-status.md`](refactor-status.md), then move this directory to
> `docs/archive/refactor20261106/` (mirroring
> [`refactor20261105`](../archive/refactor20261105/)).
>
> **Predecessor:** [`docs/archive/refactor20261105/refactor-plan.md`](../archive/refactor20261105/refactor-plan.md)
> (complete). Do not re-open its `P0`–`P5` tasks; this plan uses `R`-prefixed IDs.
>
> **Baseline:** `d6dce95` plus the uncommitted working-tree changes that removed
> marker thinning, lowered the compact/visibility thresholds to 6 km / 12 km,
> and normalised the route-badge and header-icon sizes. Line numbers drift;
> **symbol names are the source of truth**.
>
> **Scope:** the whole app — 24 Swift files, ~4.5k lines. No feature work
> (departures, vehicles, routing) is included.
>
> **Origin:** a full read of every Swift file plus a warning-free build and
> `xcodebuild test` (63 tests in 2 suites, all green) on Xcode 27.2. Every task
> below therefore addresses structural, performance, robustness, or
> documentation debt — not a currently failing test.

---

## 1. How to use this plan

- Work top-down. Phase 0 decides the questions that Phase 1 depends on; do not
  start a refactor whose acceptance criteria depend on an open decision.
- One work package per commit/PR. The suggested breakdown is in §10.
- Every task has an **Acceptance** line. It is done only when the criteria pass,
  the build stays warning-free, and the full suite stays green.
- When a task changes behaviour, update the affected document in the **same
  commit** (`docs/architecture.md`, `docs/decisions.md`,
  `docs/decisions/*.md`, `README.md`, `AGENTS.md`).
- If §9 has no outcome for a decision the task needs, stop and ask the
  developer. Do not guess.
- Record progress in [`refactor-status.md`](refactor-status.md) as phases land.

### Constraints (from `AGENTS.md`)

- Zero non-Apple dependencies.
- Native-first: never reimplement Liquid Glass, map controls, or platform
  behaviour. `.buttonStyle(.glass)`, `glassEffect`, `MapCompass`, `MapScope`.
- Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; no
  Combine, no force unwraps/casts, 4-space indentation.
- User-facing copy lives in `Localizable.xcstrings` (Polish + English).
- Tests use Swift Testing and must be hermetic (no sockets, no shared global
  state).
- One source of truth for every piece of state.

### Non-goals

- Do not migrate the SwiftUI `Map` to a `UIViewRepresentable` **unless** D1
  explicitly chooses native clustering; if it does, keep every map control and
  glass surface native.
- Do not add a third-party formatter/linter/analytics SDK.
- Do not change the public API contract or the positional tuple layout.
- Do not re-add marker thinning "because the old ADR said so"; the working tree
  deliberately removed it, and D1 must settle the replacement.

---

## 2. Definition of done

The refactor is complete when:

1. `xcodebuild build` is warning-free for app and tests (the App Intents
   metadata note is the only allowed non-source warning).
2. `xcodebuild test` passes with networking disabled, from a clean derived-data
   directory, and does not depend on the developer's `UserDefaults`.
3. The app has an assigned 1024×1024 app icon (light, dark, tinted) and a
   defined accent colour.
4. Rendered annotations are bounded by a documented strategy (D1) and a dense
   city (Warsaw/GZM) pans without sustained frame drops on hardware.
5. A cold launch of every normal city shows full markers, not compact dots;
   the PKP exception is explicit and tested.
6. One tap on a marker produces one selection, one sheet, and no stale content
   when switching between markers.
7. Rotating or pitching the map at a fixed centre issues no stops request when
   the visible Zoom-12 tile set is unchanged.
8. `MapViewModel` no longer parses strings to derive loading state, no longer
   imports SwiftUI for `withAnimation`, and contains no `UserDefaults` access.
9. Model files contain no SwiftUI/SF Symbol presentation; `RouteType` UI lives
   in `RouteType+UI.swift` (or ADR-0004 is amended with a reason).
10. No test uses a `while … { await Task.yield() }` spin loop or mutates
    `UserDefaults.standard`.
11. `docs/architecture.md`, ADR-0002, ADR-0007, and `docs/decisions.md` agree
    with the shipped implementation.
12. `scripts/check-toolchain.sh`, the build, and the tests run in one CI job.

---

## 3. Verification workflow

```bash
# Toolchain gate
./scripts/check-toolchain.sh

# Build
xcodebuild -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# Tests (pick an installed simulator)
xcodebuild test -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

Additional gates:

- **Hermetic tests:** run once with Wi-Fi/Ethernet off, and once after deleting
  the app's `UserDefaults` domain.
- **Random order:** run the suite twice in a row; Phase 6 must make it stable.
- **Memory/rendering:** Instruments (Animation Hitches + Memory) while panning
  Warsaw and GZM at the default zoom, and at the stop-visibility boundary.
- **Manual QA matrix:** cold launch, city switch, airplane mode, denied
  location, double-tap location, rotate/pitch at fixed centre, marker A → B →
  close → A, Dynamic Type XXL, landscape, iPad if supported.
- **Preview check:** Xcode previews must not hit the network (Phase 2, R2-9).

---

## 4. Phase 0 — Decisions, guardrails, release blockers

### [x] R0-1 Add a reproducible verification gate

**Files:** new `.github/workflows/ci.yml` (or `scripts/verify.sh`),
`scripts/check-toolchain.sh`, `README.md`.

**Problem:** `README.md` says to run `check-toolchain.sh` in CI, but the repo
has no CI configuration. The script also has an unreachable branch: with
`set -euo pipefail`, a failing `xcodebuild` exits before
`[[ -z "${version}" ]]` can run.

**Change:**
- Add a CI job (macOS runner) that runs the toolchain check, builds, and tests
  on an available simulator.
- Either remove the unreachable `-z` check or capture the command status
  explicitly (`version="$(xcodebuild -version 2>/dev/null || true)"` …).
- Document the job in `README.md`.

**Acceptance:** A fresh clone reproduces the baseline with one workflow; the
script fails with a clear message on an old or missing Xcode; no dead branch.

### [x] R0-2 Resolve D1 and D2 with the developer (blocking)

**Files:** this plan §9, `docs/decisions.md`.

**Problem:** The working tree removed grid thinning and lowered the thresholds
to 6 km/12 km, but ADR-0002 still mandates a 250-marker cap and the tests were
edited to assert the new behaviour instead of the intended behaviour. Agents
cannot safely refactor markers until the target strategy is known.

**Change:** Ask the developer to answer D1 (marker density) and D2 (compact /
visibility thresholds). Record the outcomes in §9 and, for D1, create
`docs/decisions/0008-marker-density.md`.

**Acceptance:** Both decisions have an owner-approved outcome; Phase 1 tasks
reference them instead of inventing a policy.

### [x] R0-3 Assign the app icon and accent colour

**Files:** `KomunikacjaWiejska/Assets.xcassets/AppIcon.appiconset/Contents.json`,
`KomunikacjaWiejska/Assets.xcassets/AccentColor.colorset/Contents.json`.

**Problem:** The icon set declares three 1024×1024 slots but **no `filename`
entries**, so the app ships with a blank icon. `AccentColor` declares no colour
components and falls back to system blue.

**Change:** Add the light/dark/tinted 1024×1024 assets (no alpha), assign them
in `Contents.json`, and define the accent colour with light/dark variants.
If artwork is not available, ask the developer rather than generating a
placeholder that might ship.

**Acceptance:** The built `.app` shows the icon in Simulator/Finder; `actool`
reports no missing-image warnings; the accent colour is intentional.

### [x] R0-4 Add a "current implementation differs" note to stale docs

**Files:** `docs/architecture.md` §1, `docs/decisions/0002-marker-density.md`,
`docs/decisions/0007-tile-cache.md`, `docs/decisions.md`.

**Problem:** Until Phase 7 reconciles the docs, every claim about thinning,
ancestor-tile coverage, and the 25 km/10 km thresholds is false. Agents reading
the docs first will implement the wrong thing.

**Change:** Add a short banner at the top of the affected documents:
"Implementation changed on 2026-11-06; see
`docs/refactor20261106/refactor-plan.md` (D1/D2). Do not follow the details
below until Phase 7 reconciles this file." Do **not** rewrite the strategy yet.

**Acceptance:** `rg "thinning|ancestor" docs/architecture.md docs/decisions*`
returns hits only inside an explicitly labelled historical/stale section.

---

## 5. Phase 1 — Regressions and user-visible risks

### [x] R1-1 Implement the D1 marker-density strategy

**Files:** `ViewModels/MapViewModel.swift` (`updateStops`, currently ~761-783),
`Views/TransitMapView.swift` (~22-35), `Views/StopMarkerView.swift`, tests.

**Problem:** Every cached stop inside the viewport becomes a SwiftUI
`Annotation`, and each `StopMarkerView` observes the whole view model. With the
12 km visibility radius, a dense city can render thousands of annotation views
and re-evaluate all of them on any camera change. The previous cap was removed
without a replacement.

**Change (depends on D1):**
- **If capped:** reintroduce a deterministic representative selection (keep the
  cap implementation in the view model, not the view) and document the bound.
- **If native clustering:** adopt the native map clustering path allowed by D1
  without hand-rolling an engine; keep `StopMarkerView` as annotation content.
- Keep the selected stop visible when it lies inside the viewport.
- Keep output deterministic (sorted by `id`) so repaints do not flicker.

**Acceptance:** The number of annotation views is bounded and documented. Panning
Warsaw/GZM shows no sustained hitches in Instruments. A test asserts the bound
and determinism, not the implementation detail of the grid.

### [x] R1-2 Make launch marker mode intentional (D2)

**Files:** `ViewModels/MapViewModel.swift` (`compactDisplayDistanceThreshold`,
`stopVisibilityDistanceThreshold`, `approximateDistance`),
`KomunikacjaWiejskaTests/KomunikacjaWiejskaTests.swift`
(`testCompactModeAtLaunchAndSwitch`, `testCompactDisplayMode`).

**Problem:** The threshold is 6,000 m while Warsaw's default span resolves to
≈8,880 m, so **every normal city launches in compact-dot mode**. The test was
changed to assert that behaviour instead of the product intent, and the code
comment that explained the old intent was deleted with the thinning diff.

**Change (depends on D2):**
- Choose thresholds from the product intent (full markers at the default city
  view; compact only when zoomed out; PKP explicit).
- Replace the test with one that asserts intent for all `City.allCities`
  (excluding documented exceptions), plus boundary tests exactly at the
  thresholds.
- Document the chosen numbers in `docs/architecture.md` and ADR-0007.

**Acceptance:** Cold launch of every normal city renders full markers; boundary
values are tested on both sides; PKP behaviour is intentional and tested.

### [x] R1-3 Remove selection-driven stop recomputation

**Files:** `ViewModels/MapViewModel.swift:121-126`.

**Problem:** `selectedStopID.didSet` calls `updateStops()` on every selection.
That existed only to re-insert a selected stop after grid thinning, which is
gone. Each tap now filters and sorts the whole cache for nothing.

**Change:** Delete the observer's `updateStops()` call. If the current D1
strategy still needs selected-stop preservation, express that inside
`updateStops()` (and call it when the cap changes), not as a selection side
effect.

**Acceptance:** Selecting/deselecting a marker performs no stop-array
recomputation; a regression test covers "selected stop is present in `stops`
when inside the viewport".

### [x] R1-4 Batch stop-cache merges into one observation

**Files:** `ViewModels/MapViewModel.swift:696-698` (`startFetch` success path).

**Problem:** `for stop in fetchedStops { cachedStopsByID[stop.id] = stop }`
mutates an observed dictionary once per stop, firing an `@Observable`
invalidation per element. Large responses cause hundreds of unnecessary view
updates.

**Change:** Merge into a local copy, assign once, then update `fetchedTiles`,
state, and `stops` in a single logical block. Keep the "newest response wins"
semantics per stop ID.

**Acceptance:** One fetch causes one cache invalidation (verify with a small
observation-count test or a targeted log), and the existing merge test passes.

### [x] R1-5 Make stop presentation a single source of truth

**Files:** `Views/TransitMapView.swift` (~7, 73-99),
`ViewModels/MapViewModel.swift` (`selectedStopID`, `selectedStop`).

**Problem:** Selection is driven by `Map(selection:)`, `.tag`, an extra
`.onTapGesture`, a stored `presentedStop`, and two `.sheet` modifiers. The
stored `presentedStop` is never cleared, so `presentedStop ?? selectedStop` can
flash stale content; the two sheets on one view are fragile.

**Change:**
- Keep one `selectedStopID` and derive `selectedStop` from the cache.
- Drive a single `.sheet(item:)` from a small `SheetRoute` enum
  (`.stopDetail(Stop)`, `.cityPicker`) or one `sheet(item:)` plus a separate
  presentation for the city picker attached to a different subview.
- Remove `presentedStop` and the `.onChange` copy.
- Choose one tap mechanism; if `Map` selection works for custom annotations,
  drop the extra gesture (otherwise document why both exist).
- Clear the ID in exactly one dismissal path.

**Acceptance:** Tap A → sheet A; tap B while open → sheet B; dismiss → no
selection; tap A again → sheet A (no flashing). VoiceOver still selects markers.

### [x] R1-6 Fetch only when the visible tile set changes

**Files:** `ViewModels/MapViewModel.swift` (`handleCameraChange`,
`scheduleViewportFetch`, `loadDecision`).

**Problem:** Every settled camera change schedules a viewport fetch decision.
Rotation and pitch alter `context.region` even when the centre is unchanged, so
the tile set (and therefore the bbox) changes and an in-flight request can be
cancelled only to be repeated. This is network churn during a common gesture.

**Change:** Compute the visible tile set first; if it is identical to the last
requested/covered set, skip both the debounce and any cancellation. Only cancel
in-flight work when the *coverage requirement* changes or the city changes.

**Acceptance:** Rotating/pitching at a fixed centre issues **zero** requests
and **zero** cancellations (assert via `StubStopsProvider.callCount` and a
cancellation counter); panning still fetches missing tiles.

### [x] R1-7 Meet minimum touch targets

**Files:** `Views/TransitMapView.swift:165`,
`Views/StopMarkerView.swift:100`, `Views/StopDetailSheet.swift:122-128`.

**Problem:** The 2D button and compact-marker hit area are 30 pt; the sheet
close button has no explicit 44 pt frame. Below the HIG minimum, especially for
motor-impaired users.

**Change:** Keep the visual 30 pt control but expand the interactive area to
≥44 pt (`.contentShape` + frame, or padding inside the glass button). Give the
close button a 44×44 frame without changing the glyph size.

**Acceptance:** Xcode Accessibility Inspector reports ≥44×44 for both controls;
layout at Dynamic Type XXL unchanged.

### [x] R1-8 Fix the location double-tap race and add a timeout

**Files:** `Views/MapControlsComboView.swift:80-100`,
`Services/LocationManager.swift:88-170`.

**Problem:** Every tap starts an unstructured `Task` calling
`requestCurrentLocation()`. The second tap replaces the first continuation with
`LocationError.unavailable`, so the user can receive a spurious "location
unavailable" alert while the newer request succeeds. There is also no timeout
if the delegate never answers.

**Change:**
- Disable/guard the button while a request is in flight (`isRequestingLocation`
  in the manager or a local `@State`).
- Collapse to one continuation with a documented replacement policy (resume the
  old one with `.unavailable` *and* suppress its alert, or ignore the new tap).
- Add a bounded wait (e.g. 15 s) for both the authorization decision and the
  one-shot fix; map expiry to `.unavailable`.
- Add hermetic tests for the state machine (inject a fake location source; do
  not instantiate `CLLocationManager`).

**Acceptance:** Double-tapping the location button never shows a false error and
never leaves a stranded continuation; a delegate that never calls back resolves
after the timeout.

### [x] R1-9 Bound per-city error state

**Files:** `ViewModels/MapViewModel.swift` (`errorsByCity`, `errorMessage`).

**Problem:** `errorsByCity` accumulates an entry per city for the lifetime of
the process and is only cleared for the current city. Switching A → B → A can
surface a stale error from an earlier viewport.

**Change:** Clear the entry when a fetch for that city starts or succeeds, and
drop cached error entries on city switch. Keep the "an error for A never shows
in B" invariant.

**Acceptance:** A failed fetch does not survive a city round-trip; tests cover
A-fails → B → A.

---

## 6. Phase 2 — State machine and decomposition

### [x] R2-1 Replace the stringly-typed load state

**Files:** `ViewModels/MapViewModel.swift` (`FetchState`, `isLoading`,
`fetchState`, `startFetch`, `fetchCurrentViewport`).

**Problem:** Load state is encoded as `"\(city.id):\(bbox.queryValue)"`,
cached loads write the fake key `"\(city.id):tiles"`, and `isLoading` is
`key.hasPrefix("\(selectedCity.id):")`. `.loaded`/`.failed` payloads are never
read. This is hard to reason about and easy to break if a city id ever contains
a colon.

**Change:** Introduce a typed `RequestKey` (city id + tile set or bbox) and a
small enum (`idle`, `loading(RequestKey)`, `loaded(RequestKey)` if needed).
Derive `isLoading` from the enum, not from string parsing. Delete the
`":tiles"` sentinel.

**Acceptance:** No `hasPrefix`/string interpolation-based state decisions; all
existing loading-phase and cache tests pass; new tests cover "loading city A,
switch to B" without inspecting strings.

### [x] R2-2 Remove the `shouldRepositionOnCityChange` suppression flag

**Files:** `ViewModels/MapViewModel.swift` (`selectedCity` observer, `selectCity`),
`Views/CityPickerSheet.swift`, `Views/TransitMapView.swift:98`.

**Problem:** A temporary boolean suppresses a side effect of a `didSet` because
the picker writes the binding directly. Property observers with side effects
(persist, clear cache, fetch, reposition) are hard to reason about and easy to
re-enter.

**Change:** Make `selectedCity` `private(set)`. Add explicit intents:
`selectCity(_:repositionCamera:)` and `switchToSuggestedCity()`. Have the picker
call `selectCity` (a callback or a small binding wrapper) instead of assigning
the property. Move persistence/cache/fetch side effects into the intent method.
Decide and document whether the picker always repositions (today it does).

**Acceptance:** `rg shouldRepositionOnCityChange` returns nothing; both picker
selection and suggestion switching are covered by tests; the camera policy is
documented.

### [x] R2-3 Make the camera state internally consistent

**Files:** `ViewModels/MapViewModel.swift` (`CameraState`, `currentCenter`,
`visibleRegion`, `centerOnUserLocation`, `resetPitchTo2D`).

**Problem:** `CameraState` stores both `center` and `region.center`, which can
diverge. `centerOnUserLocation` and `resetPitchTo2D` update one field only;
`visibleRegion`'s setter silently ignores `nil` and exists mainly as a test
hook.

**Change:**
- Store one centre (derive `region.center` or remove the duplicate field).
- Make `cameraState` `private(set)`; programmatic camera moves go through
  methods that update every derived value atomically.
- Remove `visibleRegion`'s write path from production; give tests a seam they
  can call (e.g. a `nonisolated` pure helper for region math, or an internal
  `applyCameraUpdate` under `#if DEBUG`/`@testable`).
- Add an invariant check/test after centre, pitch reset, and city reposition:
  `center == region.center`, finite spans, positive distance.

**Acceptance:** No diverging centre/region after any public camera method;
production code never writes `visibleRegion`; tests no longer rely on a
production-only setter.

### [x] R2-4 Inject camera persistence

**Files:** `ViewModels/MapViewModel.swift:97, 262-290, 327-331`; new
`Services/CameraStore.swift` (or `DefaultsStoring`).

**Problem:** The view model reads and writes `UserDefaults.standard` directly,
including a duplicated magic key `"lastSelectedCityId"`. Tests mutate the
developer's defaults to exercise restore.

**Change:** Define a small `DefaultsStoring` protocol (get/set typed values or
raw `Any?`), a `UserDefaults` implementation, and a `DefaultsKey` enum. Inject
it into `MapViewModel`. Validate restored coordinates in one pure function.
Keep production behaviour identical.

**Acceptance:** `rg "UserDefaults"` under `ViewModels/` returns nothing; the
restore test uses an ephemeral suite (`UserDefaults(suiteName:)` removed in
`defer`); production still restores the last city and camera.

### [x] R2-5 Split `MapViewModel` into focused units

**Files:** `ViewModels/MapViewModel.swift` (797 lines) and new files under
`Models/`/`Services/`.

**Problem:** One class owns camera math, persistence, tile cache, networking,
loading/error state, city suggestion, and animations. It imports SwiftUI only
for `withAnimation`. `MapMode`, `StopLoadingPhase`, `CameraState`, and the
coordinate epsilon helper live in this file.

**Change (incremental, one commit per extraction):**
1. Move `MapMode`, `StopLoadingPhase`, `CameraState`, and the
   `CLLocationCoordinate2D` epsilon helper to `Models/` (or a new
   `ViewModels/CameraState.swift` if they are view-model-specific).
2. Extract `StopCache` (dictionary + tile set + `isCovered` + merge) and
   `ViewportLoadPlanner` (visible tiles → decision → bbox) as value types or a
   small actor-isolated service, with pure tests.
3. Extract `CameraPersistence` (R2-4) and `RegionSuggestion` (pure function
   already exists — move it).
4. Remove the SwiftUI import; return an animation intent or let the view layer
   wrap calls in `withAnimation`.

**Acceptance:** `MapViewModel` is under ~300 lines with one responsibility per
collaborator; no SwiftUI import; no behaviour change; all existing tests pass
with only access-level adjustments.

### [x] R2-6 Inject the location source

**Files:** `ViewModels/MapViewModel.swift:384-390`,
`Services/LocationManager.swift`, `Views/TransitMapView.swift`.

**Problem:** `releaseTrackingIfRoaming` reaches into `LocationManager.shared`,
making the view model depend on a singleton and impossible to test without a
real location.

**Change:** Define `LocationProviding: Sendable` (authorization state + current
location or an async fix) and inject it, following the existing
`StopsProviding` pattern. Keep `LocationManager` as the production
implementation.

**Acceptance:** `rg "LocationManager.shared"` in `ViewModels/` returns nothing;
tracking-release behaviour is tested with a stub coordinate.

### [x] R2-7 Centralise constants and identifiers

**Files:** `ViewModels/MapViewModel.swift`, `Models/City.swift`,
`Models/MapTile.swift`, tests.

**Problem:** `"pkp"` appears four times, `111_000` twice, the defaults key
`"lastSelectedCityId"` three times, and thresholds are instance properties.
`MapMode.rawValue` is documented as persisted even though the mode is never
persisted.

**Change:** Add `City.pkp` (and use it in `coverageRadiusMeters`, the restore
special case, and suggestion filtering), a shared
`metersPerDegreeLatitude` constant, `DefaultsKey` members, and `static let`
thresholds. Either persist `selectedMapMode` (and test it) or fix the comment.

**Acceptance:** `rg '"pkp"|111_000|lastSelectedCityId'` finds no production
literal outside the defining constant; tests reference the constants.

### [x] R2-8 Adopt one logging policy

**Files:** `ViewModels/MapViewModel.swift` (15 `#if DEBUG` blocks),
`Services/ZbiorkomAPIClient.swift` (8), `Services/LocationManager.swift`,
`Extensions/Logger+Categories.swift`.

**Problem:** Debug logging is wrapped in 23 `#if DEBUG` blocks, bloating every
fetch path, while `LocationManager` logs unconditionally. Reviewing a control
flow requires skipping half the function.

**Change:** Use `os.Logger` unconditionally with `privacy:` annotations (cheap
and release-safe), or define small `#if DEBUG` helper functions for the few
genuinely sensitive details (decoding diagnostics). Update the `Logger.mapCache`
doc comment, which still mentions thinning and cache invalidation.

**Acceptance:** No `#if DEBUG` in the fetch/camera control flow; logs remain
useful in Console; no user data is logged as public.

### [x] R2-9 Fix view-model ownership and preview hermeticity

**Files:** `Views/TransitMapView.swift:5`, `ContentView.swift`,
`KomunikacjaWiejskaApp.swift`.

**Problem:** `@State private var viewModel = MapViewModel()` constructs (and
reads defaults for) a throwaway view model on every `TransitMapView` init, and
the `ContentView` preview runs `.task` against the real API. `ContentView` is a
pass-through wrapper.

**Change:** Initialise the view model once with an explicit initializer or an
injectable factory; add a preview/stub initializer. Remove `ContentView` if it
adds nothing, or give it the actual app-level composition (environment
injection). Ensure previews use `StubStopsProvider` and never call `.task` with
the production client.

**Acceptance:** Re-initialising the view does not allocate a discarded VM;
previews work with networking disabled; no `#Preview` triggers a real request.

---

## 7. Phase 3 — Views and presentation

### [x] R3-1 Simplify `StopMarkerView`'s dual API

**Files:** `Views/StopMarkerView.swift`.

**Problem:** Two initializers plus three mirrored optionals
(`explicitIsSelected`, `explicitIsCompact`, `explicitHeading`) exist so previews
and tests can bypass the view model. Production therefore has two
representations of the same inputs.

**Change:** Pass a single small `MarkerPresentation` value (or primitives:
`isSelected`, `isCompact`, `heading`) from `TransitMapView`; remove the
view-model initializer. Derive everything else from `Stop` and `RouteType`.

**Acceptance:** One initializer; previews/tests construct the value directly; no
optional-mirroring properties.

### [x] R3-2 Hide annotation titles natively in compact mode

**Files:** `Views/TransitMapView.swift:104-106`.

**Problem:** `markerTitle(for:)` returns `""` in compact mode. Empty titles are
a hack that can confuse accessibility and map APIs.

**Change:** Pass the real title and apply `.annotationTitles(.hidden)` when
compact (or omit the title from the annotation initializer and keep the
accessibility label on the marker). Verify VoiceOver still announces the stop.

**Acceptance:** No empty-string titles; VoiceOver reads the stop name in both
modes; compact mode has no visible labels.

### [x] R3-3 Finish the design-token pass

**Files:** `Views/DesignTokens.swift`, `Views/StopMarkerView.swift`,
`Views/StopDetailSheet.swift`, `Views/MapControlsComboView.swift`.

**Problem:** `markerSelectedSize` and `markerCompactSize` are unused, while the
view hardcodes `1.25`, `min(badgeSize * 0.3, 9)`, `240` detent height, `18`,
`14`, and `40`. Tokens and implementation disagree.

**Change:** Delete unused tokens or use them; replace remaining magic numbers
that express layout intent; leave one-off drawing ratios local but named.
Document the selected-marker scale and compact-size rules.

**Acceptance:** `rg` shows no unused `DesignTokens` member; layout is unchanged
at default and XXL Dynamic Type (screenshot diff).

### [x] R3-4 Modernise map controls and attribution

**Files:** `Views/MapControlsComboView.swift`.

**Problem:** Uses the legacy `Alert(...)` builder, references `UIApplication`
without importing UIKit, fires an unbounded `Task` per location tap, and shows
"© OpenStreetMap" under Apple Maps tiles.

**Change:**
- Use the modern `alert(_:isPresented:presenting:)` API.
- Import `UIKit` explicitly (or use `@Environment(\.openURL)` only and pass the
  settings URL).
- Reuse the R1-8 in-flight guard.
- Correct the attribution: Apple Maps needs no OSM credit; if zbiorkom.live data
  requires attribution, name the data provider accurately and place the credit
  where the data appears.

**Acceptance:** No deprecation/availability warnings; one alert per failed
request; attribution is accurate and localized.

### [x] R3-5 Clean up the city picker

**Files:** `Views/CityPickerSheet.swift`, `Resources/cities.json`,
`Models/City.swift`.

**Problem:** The list shows the raw API id (`warsaw`, `gzm`, `pkp`) as a
subtitle, and all names are Polish even in the English locale. This leaks
implementation detail and looks unfinished.

**Change (depends on D4):** Show the localized network type or nothing instead
of the raw id. If English names are required, add an explicit optional field to
the JSON; do not machine-translate proper nouns. Keep search across Polish
names and aliases.

**Acceptance:** No raw API ids in the UI; pl/en screenshots reviewed; search
still finds every documented alias.

### [x] R3-6 Make route-badge text contrast-safe

**Files:** `Views/StopDetailSheet.swift:26-42`.

**Problem:** API-provided route colours are always paired with `.white` text.
Light colours (yellow, pale green) make the route number unreadable.

**Change:** Choose `.white` or `.black` from the badge colour's relative
luminance, with a documented threshold. Keep the existing fallback when the hex
is invalid.

**Acceptance:** A unit test covers light and dark badge colours; Increase
Contrast still passes.

### [x] R3-7 Finish sheet sizing and accessibility

**Files:** `Views/StopDetailSheet.swift`, `Views/TransitMapView.swift:92-94`.

**Problem:** Detent height 240 is magic; the close target is below 44 pt;
`.presentationBackgroundInteraction` is enabled up through `.medium` while the
map selection can change underneath the sheet.

**Change:** Move detent values to tokens; expand the close target; verify that
map interaction while the sheet is open does not present a different stop
without intent (or disable interaction if it does). Keep `.large` available for
accessibility sizes.

**Acceptance:** Dynamic Type XXL does not clip; VoiceOver reaches close and all
content; marker taps behind the sheet behave predictably.

---

## 8. Phase 4 — Models and decoding

### [x] R4-1 Clean up `MapTile`

**Files:** `Models/MapTile.swift`, tests.

**Problem:** `init(zoom:x:y:)` silently ignores `zoom`; zoom is declared three
times (`MapTile.fixedZoom`, `MapTile.zoom`, `MapTileGrid.zoom`); and default
arguments such as `zoom: Int = zoom` shadow the type's own member.

**Change:** Keep one zoom constant. Remove the misleading initializer or make
it `init(x:y:)` only. Replace default arguments with explicit calls (or a
private overload). Document antimeridian/pole behaviour as best-effort.

**Acceptance:** `rg "init\(zoom"` returns nothing; tile tests still pass; no
behaviour change.

### [x] R4-2 Stop mislabelling stops as buses

**Files:** `Models/Stop.swift:193-195`, `Views/StopMarkerView.swift`,
`Views/StopDetailSheet.swift`.

**Problem:** `primaryVehicleType` falls back to `.bus` when `vehicleTypes` is
empty, so an unknown stop is shown with a bus icon and announced as a bus.

**Change:** Return `.unknown` and rely on the existing neutral symbol/colour.
Add a decoding/property test.

**Acceptance:** Empty `vehicleTypes` renders the unknown symbol; no screen
claims "bus" without evidence.

### [x] R4-3 De-duplicate positional decoding

**Files:** `Models/Stop.swift` (`TupleDecoding`, `StopRoute`, `Stop`,
`decodeEntrances`).

**Problem:** ~100 lines repeat `field`/`index`/`typeName` arguments, which
duplicates the property name and invites copy-paste errors. `bearing` bypasses
`TupleDecoding.decode` altogether, so its failures lack the type/field/index
context. `requireMinimumCount` silently skips validation when
`container.count == nil`.

**Change:** Add a `decode(at:as:field:in:)` helper that advances the container
and infers the index, or a `TupleReader` wrapper. Wrap the bearing decode. Make
the `count == nil` policy explicit (document that non-JSON decoders may skip
count validation, or fail).

**Acceptance:** Same diagnostics for every field including `bearing`; line count
drops materially; all malformed-payload tests pass; no force unwraps.

### [x] R4-4 Decide the fate of decoded-but-unused data

**Files:** `Models/Stop.swift` (`StopEntrance`, `StopRoute.longName/agency/city`),
`Views/StopDetailSheet.swift`.

**Problem:** Entrances are decoded, assigned synthetic IDs, and tested, but never
shown. `longName`, `agency`, and the route `city` are also unused. This is
maintenance surface for no user value.

**Change (depends on D3):** Either surface entrances in the detail sheet
(entrance name + distance/coordinate link) or remove entrance decoding from the
model until the feature exists. Do the same for unused route fields. Do not keep
a "future" field without an ADR note.

**Acceptance:** No unused public model properties remain (or the plan/status
records why they stay); decoding tests match the model surface.

### [x] R4-5 Reconcile `RouteType` UI placement with ADR-0004

**Files:** `Models/RouteType.swift`, `Extensions/RouteType+UI.swift`, ADR-0004.

**Problem:** `systemImageName` and `defaultHexColor` live in the model while
`displayName`/`defaultColor` live in the UI extension, contradicting ADR-0004's
"UI-free model layer". `displayableCases` is used only by tests.

**Change:** Move all presentation (symbol names, colours, display names) to
`RouteType+UI.swift`; keep raw values and decoding in the model. Either use
`displayableCases` in the UI or remove it and its tests.

**Acceptance:** `Models/RouteType.swift` imports only `Foundation` and contains
no SF Symbol/hex presentation; ADR-0004 matches the code.

### [x] R4-6 Make `City` semantics explicit

**Files:** `Models/City.swift`, `Models/MapTile.swift`, tests.

**Problem:** `city(id:)` silently returns Warsaw for an unknown id, hiding
typos. `coverageRadiusMeters` derives a geographic radius from the display
span with `max(20_000, …)`, a heuristic that conflates zoom defaults with
coverage. `CityCatalog.load`'s doc says it logs on failure, but it uses `try?`
without logging.

**Change:** Return an optional (and handle the fallback at the call site with a
log) or document the fallback as intentional. Separate the geographic coverage
radius from `defaultLatitudeDelta` (either a JSON field or an explicit formula
with a comment). Log catalog load failures via `Logger`.

**Acceptance:** A missing/typo'd city id is observable; city suggestion tests
still pass; a corrupt `cities.json` logs a clear error and falls back once.

### [x] R4-7 Remove dead bounding-box plumbing

**Files:** `Models/BoundingBox.swift`, tests.

**Problem:** `BoundingBox(region:)` is used only by a test after the tile
refactor; the file imports CoreLocation without using it. `queryValue` builds a
format via string interpolation before formatting.

**Change:** Remove `init(region:)` and unused imports, or wire it back into a
real path. Simplify `queryValue` to a single format string. If tests need a
region→bbox helper, keep it in the test target.

**Acceptance:** `rg "BoundingBox\\(region:"` returns nothing in production;
`queryValue` is unchanged and tested.

### [x] R4-8 Normalise access control

**Files:** all model/view/service files.

**Problem:** Almost everything is `public` even though this is a single app
target. `public` suggests a framework API that does not exist and hides which
types are truly intended for cross-module use.

**Change (depends on D5):** Make declarations `internal` by default; keep
`public` only where a future module boundary or a documented test seam
requires it. Do not change behaviour.

**Acceptance:** The build has no access-control errors; the public surface is
small and intentional; `@testable import` covers tests.

### [x] R4-9 Clean concurrency comments and plan references

**Files:** `Models/Stop.swift`, `Models/BoundingBox.swift`,
`Services/StopsProviding.swift`, `ViewModels/MapViewModel.swift`.

**Problem:** Long comments justify `nonisolated` with archived plan phases
(`P5-3`, `D1-A`, `P2-5`), which no longer resolve. The treatment is also
inconsistent (`StopsResponse` is `nonisolated`, `Stop` is not, with no
explanation).

**Change:** Rewrite comments in terms of the current diagnostic/behaviour, not
ticket IDs. Confirm whether `Stop`/`StopRoute` need the same treatment; add a
comment only where the compiler actually requires the attribute.

**Acceptance:** `rg "P[0-9]-[0-9]|D[0-9]-A"` under `KomunikacjaWiejska/`
returns nothing; the Swift 6 build is clean; each `nonisolated` has a current,
verifiable reason.

---

## 9. Phase 5 — Networking

### [x] R5-1 Bound and sanity-check the retry policy

**Files:** `Services/ZbiorkomAPIClient.swift:107-165`.

**Problem:** The retry loop is `while true`; the bound exists only because two
branches increment `attempt`. A future `continue` without an increment hangs.
It retries `.notConnectedToInternet` after 200–600 ms, which cannot recover and
doubles the offline wait. It ignores `Retry-After` on 5xx.

**Change:** Use an explicit `for attempt in 0...Self.maxRetryCount` loop (or a
`while attempt <= max` with a single increment). Do not retry
`.notConnectedToInternet`; keep `.timedOut`, `.networkConnectionLost`, and
`.cannotConnectToHost` if D6 says so. Optionally honour `Retry-After` up to a
cap (ask the developer; not required for MVP).

**Acceptance:** A test proves at most one retry for every error path and that
4xx/offline are never retried.

### [x] R5-2 Remove duplication in URL building and decoding

**Files:** `Services/ZbiorkomAPIClient.swift:47-105`.

**Problem:** The base URL is an optional from a compile-time literal (the guard
is unreachable in practice), the decoding catch repeats the throw in
`#if DEBUG`/`#else`, and a new `JSONDecoder` is allocated per request.

**Change:** Keep the defensive URL construction but document that it is
defensive, not expected. Build the error payload once and throw once. Reuse a
`static let` decoder (it is not shared across isolation domains unsafely if
confined to the actor) or keep per-request if the team prefers simplicity —
document the choice. Keep DEBUG diagnostics in the associated value only.

**Acceptance:** One throw per error path; no duplicated `#if DEBUG` blocks in
the catch; tests unchanged.

### [x] R5-3 Preserve cancellation semantics

**Files:** `Services/ZbiorkomAPIClient.swift`, `ViewModels/MapViewModel.swift`.

**Problem:** `backoff()` throws `CancellationError`, which escapes the
`URLError` catch unmapped; the view model then maps any error to a generic
message. This is currently hidden by the generation guard, but the layering is
fragile.

**Change:** Rethrow `CancellationError` explicitly (or map it to a dedicated
error) and have the view model ignore cancellations deterministically.

**Acceptance:** A cancelled request never surfaces an error capsule; test with a
provider that cancels mid-flight.

---

## 10. Phase 6 — Tests

### [x] R6-1 Replace spin-wait synchronization

**Files:** `KomunikacjaWiejskaTests/KomunikacjaWiejskaTests.swift` (~15 sites,
e.g. `while viewModel.isLoading { await Task.yield() }`).

**Problem:** Busy-wait loops can hang the suite forever if a state transition is
missed, and they burn the cooperative pool.

**Change:** Add a `waitUntil(timeout:_:)` helper backed by
`confirmation`/polling with a time limit, or use a test double continuation that
the test opens deterministically (`StubStopsProvider.openGate` already exists).
Fail with a clear message on timeout.

**Acceptance:** No `while … Task.yield()` in tests; a deliberately broken
transition fails fast with a diagnostic; the suite runtime stays comparable.

### [x] R6-2 Isolate defaults and shared state

**Files:** `KomunikacjaWiejskaTests/KomunikacjaWiejskaTests.swift`
(`testCameraPersistenceAndRestoration`), `MockURLProtocol.swift`,
`ZbiorkomAPIClientTests.swift`.

**Problem:** The persistence test mutates `UserDefaults.standard` while other
tests run in parallel; restore is best-effort and order-dependent.
`MockURLProtocol.handler` is process-wide.

**Change:** Inject an ephemeral defaults store (R2-4) or a unique suite name
per test, removed in `defer`. Wrap `MockURLProtocol.handler` in a helper that
sets and clears it (`withMockHandler`). Mark suites `.serialized` only where a
shared global genuinely remains.

**Acceptance:** Tests pass in random order and repeated runs; no test reads or
writes the standard suite; no handler leaks between tests.

### [x] R6-3 Split and rename the test target

**Files:** `KomunikacjaWiejskaTests/*.swift`.

**Problem:** A 1,217-line file named "Zbiorkom Models & Decoding Tests" also
contains view-model, localization, and UIKit sizing tests.

**Change:** Split by unit: `StopDecodingTests`, `MapTileTests`,
`CityCatalogTests`, `MapViewModelTests`, `LocationStateTests`,
`PresentationTests`, `APIClientTests`. Keep fixtures in one place.

**Acceptance:** No test file above ~400 lines; suite names describe their unit;
no coverage loss (assert the test count).

### [x] R6-4 De-brittle assertions

**Files:** tests.

**Problem:** `City.allCities.count == 66`, exact SF Symbol names, and
hard-coded thresholds assert data/implementation rather than behaviour.

**Change:** Assert catalog invariants (unique ids, documented cities present)
instead of a literal count. Test the symbol *mapping contract* (non-empty,
distinct for `.unknown`) rather than exact strings, unless the symbol is a
product decision. Derive threshold tests from the constants.

**Acceptance:** Adding a city or changing a symbol without changing behaviour
does not fail unrelated tests.

### [x] R6-5 Simplify the stubs

**Files:** `StubStopsProvider.swift`, `MockURLProtocol.swift`.

**Problem:** `StubStopsProvider` has four fixture sources with implicit
precedence (`overrideStops` → `resultsByCity` → `error` → `stops`).

**Change:** Replace them with one result closure (`(String, BoundingBox?) ->
Result<[Stop], Error>`) plus the gate. Keep the call/bbox recording. Add a
cancellation counter for R1-6/R5-3.

**Acceptance:** Tests configure one closure; precedence is explicit in the
helper, not the stub; all existing tests migrate.

### [x] R6-6 Add regression tests for this plan

Minimum new coverage:
- marker bound/determinism (R1-1) and launch marker mode for all cities (R1-2);
- selection does not recompute stops (R1-3);
- one cache invalidation per fetch (R1-4);
- sheet A → B → close → A (R1-5, manual if not UI-testable);
- rotation/pitch issues no request (R1-6);
- location double-tap and timeout state machine (R1-8);
- typed load state across city switches (R2-1);
- camera invariant after every public move (R2-3);
- defaults restore with an ephemeral store (R2-4);
- unknown vehicle type renders `.unknown` (R4-2);
- retry bound and no offline retry (R5-1);
- cancellation produces no user-facing error (R5-3).

**Acceptance:** Every task above that changes behaviour has at least one test
(or a documented manual-QA line for UI-only behaviour).

---

## 11. Phase 7 — Documentation, repo, release

### [ ] R7-1 Reconcile all architecture documents

**Files:** `docs/architecture.md`, `docs/decisions.md`,
`docs/decisions/0002-marker-density.md`,
`docs/decisions/0007-tile-cache.md`, `README.md`, `AGENTS.md`.

**Problem:** `architecture.md:21-23` still claims ancestor-tile coverage,
"roughly three tiles per viewport", 250-marker thinning, and a thinned render
set. ADR-0002 is "Accepted" for a deleted feature. ADR-0007 specifies 25 km /
10 km thresholds and a thinning pass, while its own text says there is no tile
hierarchy. `decisions.md` repeats the ancestor claim. This is actively
misleading.

**Change:**
- Rewrite architecture §1 to the shipped fetch/density/camera strategy.
- Mark ADR-0002 **Superseded by ADR-0008** (D1) or restore it if D1 chooses a
  cap; never leave it Accepted for deleted code.
- Update ADR-0007 thresholds, the flat-tile wording, and remove the thinning
  reference.
- Fix `decisions.md` summaries and any cross-references.
- Update `README.md`/`AGENTS.md` only after the code and docs agree.

**Acceptance:** A new agent reading `AGENTS.md` → docs finds no claim
contradicted by the code; `rg "thinning|ancestor|25_000|maxRenderedStops"` in
current docs points only at historical ADRs or the new ADR-0008.

### [ ] R7-2 Final verification

- Clean derived data; run build + tests.
- Run with networking disabled.
- Run the manual QA matrix in §3.
- Confirm the app icon and accent colour.
- Measure dense-city panning once more.

**Acceptance:** All §2 criteria pass; the status file records commands, counts,
and remaining manual checks.

### [ ] R7-3 Close the plan

**Files:** `refactor-status.md`, this plan, `docs/archive/README.md`,
`AGENTS.md`, `README.md`.

**Change:** Mark every task `[x]`, record the verification snapshot, add the
directory to `docs/archive/README.md`, move `docs/refactor20261106/` to
`docs/archive/refactor20261106/`, and update links.

**Acceptance:** No dangling links; the archive index lists the plan; the active
docs index points at the archive entry.

---

## 12. Suggested commit sequence

1. `chore: add CI verification and fix toolchain script` (R0-1)
2. `docs: flag stale marker/tile decisions` (R0-4) — after R0-2 records decisions
3. `feat: assign app icon and accent colour` (R0-3)
4. `perf: bound rendered markers per D1` (R1-1, R1-3)
5. `fix: intentional launch marker mode and thresholds` (R1-2)
6. `perf: batch stop-cache merges` (R1-4)
7. `fix: single source of truth for stop sheet` (R1-5)
8. `fix: fetch only on coverage changes` (R1-6)
9. `fix: hit targets and location request state` (R1-7, R1-8)
10. `refactor: typed load state and city selection intents` (R2-1, R2-2, R1-9)
11. `refactor: consistent camera state` (R2-3)
12. `refactor: inject persistence and location; extract cache/planner` (R2-4…R2-6)
13. `refactor: constants, logging, view ownership` (R2-7…R2-9)
14. `refactor: marker/annotation/token/control cleanup` (R3-1…R3-7)
15. `refactor: model and decoding cleanup` (R4-1…R4-9)
16. `fix: retry bounds, cancellation, client cleanup` (R5-1…R5-3)
17. `test: async helpers, isolation, split suites, regressions` (R6-1…R6-6)
18. `docs: reconcile architecture and ADRs; archive plan` (R7-1…R7-3)

Phases 2 and 3 can interleave once R2-1/R2-3 land; Phase 4 is independent of
Phase 3 except for `RouteType+UI` imports. Keep each extraction in its own
commit so regressions are attributable.

---

## 13. Open decisions

| ID | Decision | Options | Recommended / Outcome | Blocks |
|---|---|---|---|---|
| D1 | Marker density | A: deterministic cap; B: native `MKMapView` clustering; C: accept all annotations | **Resolved: Option A** (ADR-0008, 250 cap with spatial grid & selection preservation) | R1-1, R7-1 |
| D2 | Compact/visibility thresholds | A: full markers at default city zoom (raise compact above ≈9 km); B: keep 6 km/12 km and accept dots at launch | **Resolved: Option B** (6,000 m compact / 12,000 m visibility; compact at launch accepted) | R1-2, R7-1 |
| D3 | Decoded entrances/route metadata | A: surface entrances in the sheet; B: drop until a feature needs them | B for now; add back with the feature | R4-4 |
| D4 | City-name localization | A: proper nouns only, remove raw ids; B: add English names to `cities.json` | A | R3-5 |
| D5 | Access control | A: internal by default (app target); B: keep `public` for a future framework | A | R4-8 |
| D6 | Retry set | A: timeout/connection-lost/cannot-connect; B: add offline; C: add `Retry-After` | A; never retry offline | R5-1 |
| D7 | Location timeout | 10 s / 15 s / no timeout | **Resolved: 15 s** (matching request timeout) | R1-8 |
| D8 | `ContentView` | A: remove (App → TransitMapView); B: keep as composition root | B if it later hosts environment injection; otherwise A | R2-9 |

---

## 14. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Reintroducing a marker cap hides stops users expect to see | Medium | D1 decides the product trade-off; keep the selected stop and document the representation rule |
| Native `MKMapView` clustering regresses Liquid Glass chrome | Medium | Keep SwiftUI `Map` unless D1 explicitly chooses B; never hand-roll controls |
| Threshold changes whipsaw the UX twice | Medium | Settle D2 before editing tests; assert intent once |
| Extracting `MapViewModel` breaks hidden coupling (camera + fetch + suggestion) | High | Pure-value extractions first (cache, planner, persistence), behaviour-preserving commits, tests after each |
| Ephemeral `UserDefaults` changes restore semantics | Low | Test migration first (R2-4), then production switch |
| Test rewrite masks a real regression | Medium | Keep the test count and run both old and new helpers until parity |
| Docs are edited twice (R0-4 then R7-1) | High | R0-4 only adds banners; the real rewrite is R7-1 after D1/D2 |
| App icon artwork is unavailable | Medium | Ask the developer; do not ship a placeholder or an empty set |

---

## 15. Traceability — findings from the 2026-11-06 review

| # | Finding | Task |
|---|---|---|
| 1 | Marker cap removed; no bounded annotation strategy | R1-1 |
| 2 | Default city view is compact (6 km threshold vs ≈8.9 km launch distance) | R1-2 |
| 3 | `selectedStopID.didSet` recomputes stops for a deleted feature | R1-3 |
| 4 | Cache merged one element at a time (observation churn) | R1-4 |
| 5 | `presentedStop` + two sheets + three selection writers | R1-5 |
| 6 | Rotation/pitch causes redundant fetches and cancellations | R1-6 |
| 7 | 30 pt hit areas for 2D button/markers; close button undersized | R1-7 |
| 8 | Location double-tap can show a false failure; no timeout | R1-8 |
| 9 | `errorsByCity` grows and survives city round-trips | R1-9 |
| 10 | String-prefix `isLoading`, `"…:tiles"` sentinel, unused state payloads | R2-1 |
| 11 | `shouldRepositionOnCityChange` suppression flag | R2-2 |
| 12 | `center` vs `region.center` divergence; production-only `visibleRegion` setter | R2-3 |
| 13 | `UserDefaults.standard` inside the view model; duplicated magic key | R2-4 |
| 14 | 797-line `MapViewModel`; SwiftUI import for animation | R2-5 |
| 15 | `LocationManager.shared` hidden dependency | R2-6 |
| 16 | Magic `"pkp"`, `111_000`, thresholds, defaults keys | R2-7 |
| 17 | 23 `#if DEBUG` blocks; inconsistent logging | R2-8 |
| 18 | `@State viewModel = MapViewModel()`; previews hit the network; trivial `ContentView` | R2-9 |
| 19 | `StopMarkerView` dual initializer/optional mirrors | R3-1 |
| 20 | Empty annotation title hack | R3-2 |
| 21 | Unused tokens vs hardcoded sizes | R3-3 |
| 22 | Legacy `Alert`, implicit UIKit, OSM attribution under Apple Maps | R3-4 |
| 23 | Raw city ids in picker; Polish-only names in English locale | R3-5 |
| 24 | White text on arbitrary route colours | R3-6 |
| 25 | Magic sheet detents, undersized close target | R3-7 |
| 26 | `MapTile(zoom:)` ignores zoom; triple zoom constants | R4-1 |
| 27 | `primaryVehicleType` defaults to `.bus` | R4-2 |
| 28 | Repetitive tuple decoding; unwrapped bearing errors | R4-3 |
| 29 | Entrances/route metadata decoded but unused | R4-4 |
| 30 | `RouteType` UI split contradicts ADR-0004; unused `displayableCases` | R4-5 |
| 31 | `City.city(id:)` silent Warsaw fallback; coverage heuristic; missing log | R4-6 |
| 32 | Dead `BoundingBox(region:)`; unused imports | R4-7 |
| 33 | `public` everywhere in an app target | R4-8 |
| 34 | `nonisolated` comments reference archived phases; inconsistent treatment | R4-9 |
| 35 | `while true` retry; retries offline; ignores `Retry-After` | R5-1 |
| 36 | Duplicated throw in decoding catch; optional literal base URL; decoder per request | R5-2 |
| 37 | `CancellationError` escapes unmapped | R5-3 |
| 38 | `while … Task.yield()` test synchronization | R6-1 |
| 39 | Tests mutate `UserDefaults.standard`; process-wide URL handler | R6-2 |
| 40 | 1,217-line test file with a misleading suite name | R6-3 |
| 41 | Brittle city-count/symbol assertions | R6-4 |
| 42 | Stub with four implicit fixture sources | R6-5 |
| 43 | Architecture/ADR drift (thinning, ancestor tiles, thresholds) | R0-4, R7-1 |
| 44 | Empty app icon set; undefined accent colour | R0-3 |
| 45 | No CI; unreachable toolchain-script branch | R0-1 |

---

## 16. Quick wins (first session)

If there is only time for a short session, do these in order:

- [ ] R0-2: get D1/D2 answers before touching markers.
- [ ] R0-3: assign the app icon — it is a shipping blocker.
- [ ] R1-3: delete the selection-driven `updateStops()` call.
- [ ] R1-4: batch the cache merge.
- [ ] R1-7: expand the 30 pt hit areas.
- [ ] R2-7: introduce `City.pkp`, the metres-per-degree constant, and
  `DefaultsKey` (mechanical, no behaviour change).
- [ ] R0-4 + R7-1 doc banners (cheap, prevents other agents following stale
  docs).

These are independently mergeable, low-risk, and remove the most misleading or
user-visible issues while the larger decisions are pending.
