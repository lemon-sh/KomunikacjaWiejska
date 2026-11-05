# Code Quality Remediation Plan

> Working backlog for future agents. Delete or archive this file once every phase is complete.
>
> **Baseline:** `34671bd` (`initial implementation`, 2026-11-05) plus the uncommitted working-tree changes (`await [` in `ZbiorkomAPIClient`, `nonisolated struct StopsResponse`, `.onMapCameraChange(frequency: .onEnd)`).
> **Line numbers** below refer to that baseline and will drift as the code changes; use the symbol names as the source of truth.
> **Scope:** the whole app (17 Swift files, roughly 1.2k lines), not a specific feature.

---

## 1. How to use this plan

- Work top-down. Phases are ordered by risk and dependency; do not start a later phase's refactor before the earlier phase's tests are green.
- Keep each work package to one focused commit/PR. The suggested commit breakdown is in §10.
- Every task has an **Acceptance** line. A task is only done when the acceptance criteria pass and no new build warnings are introduced.
- When a task changes behaviour, update the relevant doc (`docs/architecture.md`, `docs/api.md`, `docs/cities.md`) in the same commit.
- If a decision in §9 is still open, stop and ask the developer rather than guessing.

### Constraints (from `AGENTS.md`)

- Zero non-Apple dependencies. Do not add Alamofire, MapLibre, SwiftLint-on-CI, etc.
- Native-first: do not reimplement Liquid Glass, map controls, or platform behaviour. Use `.buttonStyle(.glass)`, `MapCompass`, `MapScaleView`, etc.
- Swift 6 patterns: `@Observable`, `async`/`await`, no Combine, no force unwraps/casts, 4-space indentation.
- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`).
- One source of truth for state. Prefer dependency injection over singletons in testable code.

---

## 2. Definition of done

The remediation is complete when:

1. `xcodebuild build` succeeds for the app and tests with **zero warnings** (or an explicitly documented allow-list).
2. `xcodebuild test` is **fully hermetic**: no test opens a socket, and the suite passes with the network disabled.
3. Launching the app performs **exactly one** stops request per city.
4. Switching city never shows the previous city's stops and never leaves a spinner stuck.
5. Initial map view is not in compact mode for any city in `City.allCities`.
6. The bearing notch renders at the correct angle relative to the badge for 0°, 90°, 180°, and 270°.
7. Denied location access presents an actionable state (Settings deep link), not a dead button.
8. No production code contains `!` force unwraps, `await` on non-async expressions, or `nonisolated`/`@preconcurrency` band-aids without a comment explaining why.
9. `docs/` matches the implementation (city count, fetch strategy, performance strategy, glass APIs).
10. Remaining known limitations are documented as issues, not hidden in comments.

---

## 3. Verification workflow

Use Xcode tools when running inside Xcode (`BuildProject`, `RunAllTests`, `XcodeRead`, `XcodeWrite`). From the shell:

```bash
# Available simulators
xcrun simctl list devices available

# Build (replace the destination with an installed simulator)
xcodebuild -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# Tests
xcodebuild test -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Additional checks:

- **Hermetic test gate:** run the suite once with Wi-Fi/Ethernet disabled (or with a `URLProtocol` that fails all requests) and confirm it stays green.
- **Manual QA matrix:** cold launch, city switch (cached and uncached), airplane mode, denied location, 3D pitch + 2D reset, stop selection + sheet drag, dynamic type XXL, small device (iPhone SE-class if supported).
- **Memory:** visit 5+ large cities and confirm `stopsCache` stops growing (after P2-3).

---

## 4. Phase 0 — Make the test harness safe (blocking)

Nothing else can be validated reliably until tests stop touching the production API.

### [x] P0-1 Introduce an injectable API abstraction

**Files:** `Services/ZbiorkomAPIClient.swift`, `ViewModels/MapViewModel.swift`, tests.

**Problem:** `MapViewModel` depends on the concrete `ZbiorkomAPIClient` actor. The injection point exists but tests never use it, so every VM test performs a live request.

**Change:**
- Add a narrow protocol, e.g. `protocol StopsProviding: Sendable { func fetchStops(city: String, bbox: BoundingBox?) async throws -> [Stop] }`.
- Make `ZbiorkomAPIClient` conform.
- Type `MapViewModel.apiClient` as `any StopsProviding` (or a concrete test double under `#if DEBUG`).
- Add a `StubStopsProvider` actor in the test target that returns fixtures or throws on demand.

**Acceptance:** `MapViewModel` can be constructed with a stub and never starts a real request in tests.

### [x] P0-2 Remove the eager request from `MapViewModel.init`

**Files:** `ViewModels/MapViewModel.swift:106`, `Views/TransitMapView.swift:128-131`.

**Problem:** `init` starts a network task; `.onAppear` starts it again and cancels the first. Construction has side effects and tests hit the network.

**Change:**
- Delete `loadStopsForSelectedCity()` from `init`.
- Add an explicit `start()` / `loadInitialDataIfNeeded()` that is idempotent (guard on an enum state: `.idle`, `.loading(city)`, `.loaded(city)`, `.failed(city)`).
- Call it from a single `.task` (not `.onAppear`) in `TransitMapView`.
- Add `deinit { activeFetchTask?.cancel() }`.

**Acceptance:** VM construction performs no I/O; cold launch issues exactly one stops request (verify with a breakpoint/log or stub call count).

### [x] P0-3 Rewrite the tests to be hermetic

**Files:** `KomunikacjaWiejskaTests/KomunikacjaWiejskaTests.swift`.

**Problem:** `testMapViewModelControls` and `testStopsKeptInMemory` instantiate a VM with the live client, and the latter calls `loadStopsForSelectedCity()` explicitly.

**Change:**
- Inject `StubStopsProvider` in every VM test.
- Assert request counts instead of relying on `stops` being pre-populated.
- Remove `#expect(viewModel.isZoomedOutForStops == false)` once the stub property is deleted (P1-4).
- Add tests for: malformed tuple (too few elements), unknown `RouteType`, `null` bearing, empty routes/entrances, bbox query string, compact threshold boundaries, cache hit/miss, city switch while in flight, decoding error mapping.

**Acceptance:** Test suite passes with networking disabled; no `URLSession` is instantiated by tests.

---

## 5. Phase 1 — Correctness bugs

### [x] P1-1 Deduplicate stop loading

**Files:** `ViewModels/MapViewModel.swift`, `Views/TransitMapView.swift`.

**Problem:** Duplicate requests caused by `init` + `.onAppear` + manual refresh paths.

**Change:** Single `.task` entry point using the idempotent state machine from P0-2. A manual refresh button may force `.idle` first. Cancel any in-flight task before starting a new city.

**Acceptance:** One request on launch; switching A → B → A while B is loading does not leave duplicate tasks running. Add a unit test around the state machine.

### [x] P1-2 Clear stops when switching city and ignore stale responses

**Files:** `ViewModels/MapViewModel.swift:27-35, 176-211`.

**Problem:** On an uncached city switch, the previous city's `stops` remain visible until the new request finishes. Late responses are only guarded by comparing `selectedCity.id`, which is easy to get wrong.

**Change:**
- Set `stops = []` (or keep a per-city snapshot keyed by city) at the start of a city switch.
- Introduce a generation token (`let requestID = UUID()` stored on the VM) and discard results whose token no longer matches.
- Track loading/error per city, not globally, so a failed A doesn't clear B's data.
- Ensure every completion path (success, failure, cancellation, cache hit) settles `isLoading`.

**Acceptance:** City A annotations disappear immediately on switching to B; a slow A response cannot overwrite B; spinner always resolves. Tests cover the race.

### [x] P1-3 Fix compact-mode threshold

**Files:** `ViewModels/MapViewModel.swift:54-60`, `Models/City.swift:15-16`.

**Problem:** Threshold is `0.05`, default span is `0.08` (PKP `5.0`), so every city launches in compact-dot mode.

**Change:** Pick one:
- (a) raise the threshold above the largest normal city span and keep PKP in compact mode with an explicit exception, or
- (b) base compact mode on camera `distance` rather than `latitudeDelta`, so it is independent of city span.
Prefer (b) because it matches how MapKit represents zoom, then delete `compactDisplayThreshold` if it becomes unused.

**Acceptance:** Launching every city in `City.allCities` (except deliberately huge networks) shows full markers. Boundary tests at the threshold.

### [x] P1-4 Delete dead code and the test that protects it

**Files:** `ViewModels/MapViewModel.swift:63-67, 213-215`, `Models/BoundingBox.swift`, tests.

**Problem:** `isZoomedOutForStops` is hardcoded `false`, `maxSpanForStops` is unused, `selectStop(_:)` is unused, and `BoundingBox` is only used by its own test. A test asserts the stub, cementing dead behaviour.

**Change:**
- Remove `isZoomedOutForStops`, `maxSpanForStops`, and `selectStop`.
- Remove `BoundingBox` **or** wire it into the fetch path (see P2-1 / decision D1). Do not leave it production-dead.
- Update tests accordingly; remove the `isZoomedOutForStops` assertion.

**Acceptance:** No unreferenced production symbols; `rg "isZoomedOutForStops|maxSpanForStops|selectStop"` returns only the decision record in this doc.

### [x] P1-5 Make stop selection a single source of truth

**Files:** `Views/TransitMapView.swift:13-29, 132-139`.

**Problem:** `Map(selection:)` and `.sheet(item:)` independently drive `selectedStop`; `.tag(stop)` compares the entire `Stop` value (including routes/entrances) instead of an ID.

**Change (preferred):**
- Keep one stored `selectedStopID: Stop.ID?` for MapKit.
- Use `.tag(stop.id)` and a computed `selectedStop` lookup by ID.
- Present the sheet from a computed/derived binding or a separate `isShowingStopDetail` flag that is updated in one place.
- When the sheet dismisses, clear the ID exactly once.

**Acceptance:** Tap marker → sheet opens; drag sheet down → marker deselects; tap another marker while open → sheet switches content; no “ghost” selection. Selection hash cost drops to a string comparison.

### [x] P1-6 Fix the bearing-notch rotation

**Files:** `Views/StopMarkerView.swift:35-43`.

**Problem:** `.offset(y: -14)` is applied before `.rotationEffect`, so the triangle spins around its own centre at the top of the badge instead of orbiting the badge.

**Change:** Rotate a container that holds the offset triangle:

```swift
ZStack {
    Image(systemName: "triangle.fill")
        .offset(y: -14)
        .rotationEffect(.degrees(Double(bearing)))
}
```

(or apply `rotationEffect` to a parent `ZStack` whose centre is the badge centre). Keep the badge itself unrotated.

**Acceptance:** Screenshot/visual check for bearings 0, 90, 180, 270: the notch points in the travel direction while the icon stays upright.

### [x] P1-7 Fix location-authorization dead ends

**Files:** `Services/LocationManager.swift`, `Views/MapControlsComboView.swift:51-59`.

**Problem:** Once denied, the location button re-requests an authorization that can never appear. Updates run forever. Failure callback is empty.

**Change:**
- Expose a derived state (`notDetermined`, `denied`, `authorized`, `servicesDisabled`).
- When denied/restricted, show an alert with “Open Settings” (`UIApplication.openSettingsURLString`) instead of silently doing nothing.
- Call `stopUpdatingLocation()` when the app backgrounds or when the user is not tracking, and `requestLocation()` for a one-shot fix.
- Implement `didFailWithError` with `Logger`/`os.Logger` and a user-visible message for `kCLErrorDenied`.
- Consider `showsUserLocation` alternatives; keep `UserAnnotation()`.

**Acceptance:** Manual test with “Deny”, “Allow Once”, and Location Services off. No infinite update loop while idle. Denied tap opens Settings.

---

## 6. Phase 2 — Performance and data lifecycle

### [x] P2-1 Decide and document the fetch strategy

**Files:** `ViewModels/MapViewModel.swift:194`, `Services/ZbiorkomAPIClient.swift:33-44`, `Models/BoundingBox.swift`, `docs/architecture.md:16-19`.

**Decision required (D1):**
- **Option A — viewport bbox (recommended for large networks):** fetch on `.onMapCameraChange(frequency: .onEnd)` with a debounce (250–400 ms), skip fetches while the gesture is active, cache per bbox/tile, and keep previous results on screen during refresh. This matches the API and the architecture doc.
- **Option B — full-city fetch (current):** keep it, but then delete `BoundingBox`, remove bbox claims from docs, and document the memory/latency trade-off.

Do not implement both accidentally. Whichever option is chosen, update `docs/architecture.md`.

**Acceptance:** Documented decision; production no longer contains unused bbox plumbing; request pattern matches the doc.

### [x] P2-2 Stop rendering every stop at every zoom level

**Files:** `Views/TransitMapView.swift:20-29`, `ViewModels/MapViewModel.swift:57-60`.

**Problem:** Compact mode only shrinks circles. SwiftUI `Annotation` is still created for every stop, so large cities will drop frames. The architecture doc claims pruning.

**Change (native-first):**
- MVP: grid-based thinning in the view model (keep at most N markers per screen tile / nearest-to-centre per grid cell) and render the thinned array.
- Better: migrate to a `UIViewRepresentable` wrapping `MKMapView` with native `MKClusterAnnotation`, or use SwiftUI `Marker` clustering if the deployment target supports it. Do **not** hand-roll a clustering engine or custom map controls.
- Keep `StopMarkerView` as the annotation content.

**Acceptance:** Pan/zoom a large city (Warsaw, GZM) at 120 Hz-capable device and confirm no sustained frame drops; marker count on screen is bounded. Document the chosen strategy.

### [x] P2-3 Bound the cache and add refresh semantics

**Files:** `ViewModels/MapViewModel.swift:76, 180-185`.

**Problem:** `stopsCache` is an unbounded in-memory dictionary with no TTL. A cached city never refreshes. Empty/partial arrays cache forever.

**Change:**
- Add a TTL (e.g. 5–10 minutes) and an explicit refresh action.
- Cap entries with LRU eviction (e.g. 5 cities) or drop non-selected cities when memory pressure is received.
- Do not cache failed or cancelled results.
- Consider a discriminator key (`city + bbox` if Option A).

**Acceptance:** Visiting 10 cities keeps cache size bounded; pull-to-refresh/reload fetches fresh data after TTL; failure does not poison the cache.

### [x] P2-4 Reduce observation churn on camera changes

**Files:** `ViewModels/MapViewModel.swift:127-143`, `Views/TransitMapView.swift:32-34`.

**Problem:** Every `.onEnd` camera change writes four observable properties, and `isCompactDisplayMode` is computed from one of them, re-evaluating every annotation.

**Change:** Group camera metrics into a single `MapCameraState` struct and only assign when it actually changes; derive compact mode from that struct. If P2-2 lands, the marker array itself should be the only thing that changes on zoom.

**Acceptance:** SwiftUI view updates per camera gesture are measurably reduced (Instruments or a temporary `_printChanges`), and annotations don’t re-render when the camera settles at the same zoom.

### [x] P2-5 Cancel work when the scene backgrounds

**Files:** `MapViewModel`, `LocationManager`, `KomunikacjaWiejskaApp`.

**Problem:** In-flight requests and GPS updates continue while backgrounded.

**Change:** Observe `scenePhase`; cancel `activeFetchTask` and stop location updates on `.background`; restart only what is needed on `.active`.

**Acceptance:** No network/GPS activity after backgrounding (Console/Instruments check).

---

## 7. Phase 3 — API and model robustness

### [ ] P3-1 Clean up `ZbiorkomAPIClient`

**Files:** `Services/ZbiorkomAPIClient.swift`.

Specific items:
- Remove `URL(string: ...)!` (line 26). Use a static `URL` built with a failable initializer and a typed `.invalidURL` error, or a `URL(string:)!` with a justified comment only if AGENTS allows it (it currently doesn't).
- Remove the meaningless `await [` (line 38) and the warning it produces.
- Fix `.invalidURL` being thrown for a non-`HTTPURLResponse`; introduce `.invalidResponse`.
- Add a dedicated `.transport(URLError)` case and map common codes (offline, timeout, cannot connect) to Polish messages.
- Preserve `DecodingError` details (use `String(reflecting:)` in DEBUG) instead of only `localizedDescription`; keep the user-facing message short.
- Build the bbox URL without mutating `url` twice; use `URLComponents` once.
- Consider a one-shot retry with jitter for transient 5xx/timeouts (do not retry 4xx).
- Set an explicit `Accept: application/json` header and document the 15 s timeout.
- Add tests using a `URLProtocol` stub for 200, error payload, malformed JSON, non-HTTP response, and timeout.

**Acceptance:** No force unwraps; no non-async `await`; error cases and localized messages covered by tests.

### [ ] P3-2 Remove the `nonisolated struct` band-aid properly

**Files:** `Models/Stop.swift:141`.

**Problem:** `public nonisolated struct StopsResponse` is an unexplained workaround for an isolation warning, and the project is still in Swift 5 language mode.

**Change:** Revert it; then resolve the actual isolation issue (likely by keeping `StopsResponse` internal, or by marking the decoding entry point `nonisolated`). If it must stay, add a comment explaining the Swift 6 diagnostic and link the issue.

**Acceptance:** Builds cleanly without the attribute, or the attribute is documented. No unexplained concurrency escapes.

### [ ] P3-3 Harden the positional tuple decoders

**Files:** `Models/Stop.swift:31-40, 59-65, 122-138`.

**Change:**
- Define index constants and a small helper that decodes `element(at:)` with a descriptive error including the type name and index.
- Validate element counts before decoding (fail with `.dataCorrupted` and a clear message).
- Validate coordinate ranges (`-90...90`, `-180...180`), normalize bearing into `0..<360`, and clamp `vehicleTypes` to known values.
- Add fixtures for: missing optional bearing, extra elements (forward compatibility), wrong types, empty arrays.
- Consider a `TupleDecodable` helper to remove the repeated `var container`.

**Acceptance:** Malformed payloads produce descriptive errors; tests cover each failure mode; no crash on any fixture.

### [ ] P3-4 Stabilize `StopEntrance.id`

**Files:** `Models/Stop.swift:43-65`.

**Problem:** `"\(name)_\(longitude)_\(latitude)"` can collide (same name/coords) and changes with float formatting. It is also inconsistent with `Hashable` synthesis.

**Change:** Since the API tuple has no entrance ID, derive a deterministic ID from the tuple position during decoding (e.g. `"\(stopID)-entrance-\(index)"`) or hash the name + indices. If entrances need to be compared/updated across refreshes, document that ordering is part of identity.

**Acceptance:** Duplicate-name fixtures get distinct IDs; IDs are stable across identical responses. Test added.

### [ ] P3-5 Make color parsing explicit and test it

**Files:** `Extensions/Color+Hex.swift`, `Models/RouteType.swift:72-88`, `Views/StopMarkerView.swift:18-20`, `Views/StopDetailSheet.swift:10-15, 46-50`.

**Change:**
- Replace the silent blue fallback with `init?(hex:)` or a named `Color(hex:fallback:)`; route callers through `RouteType`’s default.
- Validate with `Scanner`’s return value and supported lengths; reject 4/5/7-digit strings.
- Document the 8-digit format as ARGB (or switch to RGBA and update callers).
- Move SwiftUI `Color` mapping out of the `RouteType` model (e.g. `RouteType+UI.swift`) so models stay UI-free, or keep a `defaultColor` computed property in an extension.
- Add tests for `#fff`, `#ff0000`, `#80ff0000`, invalid input, and empty string.

**Acceptance:** Invalid API colors are observable (fallback is explicit), not silently Material blue. Tests cover all lengths.

### [ ] P3-6 Clean up `RouteType`

**Files:** `Models/RouteType.swift`.

- Remove the unused `import CoreLocation`.
- Decide how `.unknown` behaves in `CaseIterable`; add a `displayableCases` list if UI enumerates types.
- Give `.unknown` a neutral symbol/color that is visually distinct from real types.
- Keep decoding resilient (unknown raw → `.unknown`) and test encoding/decoding both ways.

**Acceptance:** No unused imports; tests cover unknown raw values; no UI ever shows `.unknown` as a selectable filter unless intended.

### [ ] P3-7 De-boilerplate the city catalog and add aliases

**Files:** `Models/City.swift:177-201`, `Views/CityPickerSheet.swift:12-20`, `docs/cities.md`.

**Change:**
- Move the catalog to a bundled JSON/plist resource (or generate the Swift file from `docs/cities.md`) so there is one source of truth.
- Add `aliases: [String]` and include them in `CityPickerSheet` filtering (the docs promise aliases today).
- Reconcile the 23 bundled cities with the 66 documented cities; either ship all 66 or narrow the docs to “currently bundled”.
- Keep custom `==`/`hash` on `id` and document why.

**Acceptance:** Search finds a city by any documented alias; docs and bundle agree; adding a city does not require editing decoder logic.

---

## 8. Phase 4 — UI, UX, and accessibility

### [ ] P4-1 Localize strings and separate display names from identifiers

**Files:** all views, `ViewModels/MapViewModel.swift:8-12`, `Views/MapControlsComboView.swift:74,130`.

- Add a string catalog (`Localizable.xcstrings`) with Polish (and optionally English) entries.
- Replace hardcoded Polish strings across views/models.
- Stop rendering `MapMode.rawValue`; add `displayName` (localized) and keep `rawValue`/`id` as stable identifiers.
- Align the project’s development language with the actual primary language, or keep `en` as development and provide `pl` translations.

**Acceptance:** No user-visible literal strings in views; switching locale changes labels; `MapMode` identity is locale-independent. Add a test that raw values remain stable.

### [ ] P4-2 Replace magic layout constants with safe-area-aware layout

**Files:** `Views/TransitMapView.swift:42, 114-115, 124-125, 136`, `Views/StopMarkerView.swift`, `Views/StopDetailSheet.swift`.

- Replace `Color.clear.frame(height: 52)` with `safeAreaInset`, a `GeometryReader`-derived top inset, or align controls in an overlay that respects safe areas.
- Extract shared spacing/size constants into a small `DesignTokens` enum (or use system metrics).
- Audit Dynamic Type: fixed `.system(size:)` in badges should scale or have a documented cap; sheets must not clip at accessibility sizes.
- Verify on notched and non-notched devices and in landscape.

**Acceptance:** Controls never collide with the Dynamic Island/status bar; XXL Dynamic Type remains usable; no clipped content in the stop sheet.

### [ ] P4-3 Accessibility pass

**Files:** all interactive views.

- Add `accessibilityLabel`/`accessibilityHint` to icon-only controls (map mode, location, 2D, close) and combine marker contents into one element.
- Route badges should read as “Linia 24, autobus” rather than separate icon/text elements.
- Ensure selected state is conveyed (`accessibilityAddTraits(.isSelected)`).
- Verify with VoiceOver and Increase Contrast.

**Acceptance:** VoiceOver can identify every control and marker; no unlabeled buttons remain.

### [ ] P4-4 Simplify map controls

**Files:** `Views/MapControlsComboView.swift`.

- Remove the unused `init(viewModel:)` overload that reaches into `LocationManager.shared`.
- Inject `LocationManager` from `TransitMapView` (or use `@Environment`).
- Remove redundant `@MainActor` annotations if Swift 6 allows (SwiftUI `View` is already main-actor isolated).
- Unify on `.buttonStyle(.glass)` per `AGENTS.md`; if `glassEffect`/`glassEffectUnion` is required for grouping, document why in a comment. Do not mix both styles for equivalent controls.
- Decide the fate of the hand-drawn map thumbnails: either keep them with named constants and a comment, or replace them with a simpler native preview (a static `Map` snapshot is not available synchronously; a simple icon card is acceptable). This is cosmetic, low priority.

**Acceptance:** One initializer, no global singleton fallback, consistent glass styling, no unexplained drawing magic numbers.

### [ ] P4-5 Error, loading, and offline UX

**Files:** `Views/TransitMapView.swift:43-67`, `ViewModels/MapViewModel.swift:46-47`.

- The error capsule is not actionable. Add a retry button (or tap-to-retry) and keep the last successful data visible.
- Distinguish loading states: initial load vs refresh vs city switch.
- Show a Polish, user-friendly message for offline/timeout/server errors instead of `localizedDescription` (often English).
- Ensure the capsule does not cover controls at small widths; allow two lines.

**Acceptance:** Airplane-mode launch shows a clear message plus retry; retry recovers without relaunch; cached city content stays visible during refresh.

---

## 9. Phase 5 — Project hygiene, concurrency, docs

### [ ] P5-1 Repository hygiene

- Untrack `KomunikacjaWiejska.xcodeproj/xcuserdata/.../xcschememanagement.plist` (already in `.gitignore`, still tracked).
- Confirm `.build/`, `.DS_Store`, and `buildServer.json` are ignored and not committed.
- Add a `.swift-format` config (Apple tool, no third-party dependency) if the team wants consistent formatting; otherwise document the 4-space rule.
- Consider a shared scheme committed under `xcshareddata` so CI does not depend on local user data.

**Acceptance:** `git ls-files` contains no user-specific Xcode files; a fresh clone builds.

### [ ] P5-2 Confirm the project file format

`KomunikacjaWiejska.xcodeproj/project.xcproj` is a JSON-based project file rather than the conventional `project.pbxproj`. `xcodebuild -list` works with the installed Xcode, so this appears intentional (new project format). Document the minimum Xcode version in the README/AGENTS, and add a CI check that fails loudly on an incompatible Xcode.

**Acceptance:** A documented minimum Xcode version; CI green on that version.

### [ ] P5-3 Adopt Swift 6 language mode

**Files:** project settings, `Services/LocationManager.swift`, `Models/Stop.swift`.

- Raise `SWIFT_VERSION` to `6.0` and enable strict concurrency.
- Fix the fallout properly: `CLLocationManagerDelegate` callbacks, `StopsResponse` isolation, `MapViewModel` task captures.
- Do not silence diagnostics with `@preconcurrency`/`nonisolated` without a comment.
- Add this as a separate commit after the functional work so regressions are attributable.

**Acceptance:** Swift 6 mode builds and tests cleanly; no new warnings.

### [ ] P5-4 Revisit the deployment target

`IPHONEOS_DEPLOYMENT_TARGET = 27.2` excludes almost all current devices. Confirm this is a deliberate product decision. If not, lower it to the minimum version that supports `.glass`/`.glassEffect` and adjust APIs accordingly.

**Acceptance:** Documented target; CI builds on the lowest supported runtime.

### [ ] P5-5 Reconcile documentation with code

- `docs/architecture.md`: update the fetch strategy (P2-1), pruning/clustering (P2-2), component list (remove the stale `Color+Hex` path if it moves), and the “glass materials” idiom (`.glass` vs `.ultraThinMaterial`).
- `docs/api.md`: add transport/error notes and confirm bbox semantics; keep the tuple reference in sync with P3-3.
- `docs/cities.md`: 23 vs 66 cities; alias support.
- `AGENTS.md`: link this plan, and update the file map if files move.
- Add a short `docs/decisions/` note (ADR) for D1 (bbox vs full fetch) and D2 (clustering approach). ADRs are plain Markdown; no tooling.

**Acceptance:** A new agent can read `AGENTS.md` → docs and find no claim contradicted by the code.

---

## 10. Suggested commit sequence

1. `test: add injectable stops provider; make VM tests hermetic` (P0-1, P0-3)
2. `fix: stop fetching stops from MapViewModel.init` (P0-2, P1-1)
3. `fix: clear stops and guard stale responses on city switch` (P1-2)
4. `fix: use camera distance for compact marker mode` (P1-3)
5. `refactor: remove dead stop-fetching state` (P1-4)
6. `fix: single source of truth for stop selection` (P1-5)
7. `fix: rotate bearing notch around badge center` (P1-6)
8. `fix: handle denied location access and stop idle updates` (P1-7)
9. `refactor: harden API client errors and URL building` (P3-1, P3-2)
10. `refactor: validate positional tuple decoding` (P3-3, P3-4)
11. `refactor: make color parsing explicit` (P3-5, P3-6)
12. `perf: bound stops rendering and cache` (P2-1…P2-4, after D1/D2)
13. `feat: localized strings and accessibility labels` (P4-1, P4-3)
14. `chore: safe-area layout, docs, project hygiene` (P4-2, P4-4, P4-5, P5)

Keep phases 2 and 4 independent once Phase 1 is merged. Phase 3 can proceed in parallel with Phase 2 if the same files are not touched.

Actual commit sequence used (2026-11-05):
1. `test: injectable StopsProviding; hermetic VM tests; idempotent non-init fetch` (P0-1, P0-2, P1-1, P0-3)
2. `fix: clear stops and guard stale responses on city switch; per-city loading/error` (P1-2)
3. `fix: compact markers from camera distance` (P1-3)
4. `refactor: remove dead stop-fetching state` (P1-4)
5. `fix: selection single source of truth` (P1-5)
6. `fix: bearing notch orbits badge center` (P1-6)
7. `fix: denied-location Settings deep link; one-shot fixes` (P1-7, + the redundant second init from P4-4)
8. `perf: viewport bbox fetch + thinning + cache + background cancellation` (P2-1…P2-5, D1-A/D2-A/D6 ADRs)

---

## 11. Open decisions

| ID | Decision | Options | Recommended | Blocks |
|---|---|---|---|---|
| D1 | Stops fetch strategy | A: viewport bbox + debounce; B: full-city fetch | A for large networks; B only if simplicity is preferred and docs are updated | P2-1, P2-3, P3-1 |
| D2 | Marker density strategy | A: grid thinning; B: `MKMapView` clustering; C: SwiftUI `Marker` clustering | B (native) if the architecture can absorb a representable; A as an interim | P2-2 |
| D3 | Localization scope | Polish only; Polish + English | Polish primary + English if App Store requires it | P4-1 |
| D4 | Cache freshness | TTL only; manual refresh only; both | TTL + manual refresh | P2-3 |
| D5 | Entrance identity | Tuple index; name + coordinates; server ID if added | Tuple index (deterministic) | P3-4 |
| D6 | Minimum iOS | 27.2 (current); lower to glass minimum | Ask the developer | P5-4 |

## 11.1 Decision outcomes (2026-11-05)

- **D1 → A** (viewport bbox + debounce; 350 ms). ADR: [`docs/decisions/0001-fetch-strategy.md`](decisions/0001-fetch-strategy.md).
- **D2 → A** (grid thinning, MVP; `MKMapView` clustering may be spiked later). ADR: [`docs/decisions/0002-marker-density.md`](decisions/0002-marker-density.md).
- **D6 → lower to glass minimum (iOS 26.0)**. ADR: [`docs/decisions/0003-deployment-target.md`](decisions/0003-deployment-target.md). Setting change still pending as P5-4.
- D4 resolved inside P2-3: both TTL (10 min) and manual refresh are implemented.
- D3/D5 remain open inside their work packages (P4-1, P3-4).

Progress log:
- Phase 0, Phase 1, and Phase 2 are complete (2026-11-05). P3-1's bbox query bug
  and the empty-cache guarantee were fixed as part of Phase 2; the remaining
  P3-1/P3-2 and later items are outstanding.


---

## 12. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Cluster/representable migration regresses native map controls or glass styling | Medium | Keep SwiftUI `Map` for the MVP; spike the representable in a branch; do not reimplement compass/scale |
| Swift 6 mode surfaces many concurrency errors | High | Do it after functional fixes, one module/type at a time; no blanket `@preconcurrency` |
| Lowering the deployment target removes `.glass` APIs | Medium | Confirm D6 first; keep a fallback branch for `ultraThinMaterial` only if the developer approves, not silently |
| Backend tuple order changes | Low | P3-3 count checks yield descriptive errors; add a contract test with a recorded payload |
| Cache TTL makes the map feel stale | Low | Refresh on city re-entry and expose manual reload |
| Full-city fetch causes memory spikes on GZM/Warsaw | High (current) | P2-1/P2-2/P2-3 are the mitigation; measure with Instruments |

---

## 13. Traceability — original findings

| # | Finding | Task |
|---|---|---|
| 1 | Eager network in `init` + duplicate `.onAppear` fetch | P0-2, P1-1 |
| 2 | Tests hit the production API | P0-1, P0-3 |
| 3 | Fetch-all + render-all, no pruning | P2-1, P2-2 |
| 4 | Every city launches in compact mode | P1-3 |
| 5 | Previous city’s stops remain after switching; unbounded cache | P1-2, P2-3 |
| 6 | Two sources of truth for selection; full-value `.tag` | P1-5 |
| 7 | Bearing triangle rotates around its own centre | P1-6 |
| 8 | Location denied dead end; endless updates; empty error handler | P1-7 |
| 9 | `await [` on a non-async expression | P3-1 |
| 10 | `nonisolated struct StopsResponse` band-aid | P3-2, P5-3 |
| 11 | Force unwrap of the base URL | P3-1 |
| 12 | Dead `isZoomedOutForStops`/`maxSpanForStops`/`selectStop`/`BoundingBox` | P1-4 (BoundingBox also P2-1) |
| 13 | Wrong `.invalidURL`; lossy decoding errors; raw `URLError` | P3-1 |
| 14 | Brittle duplicated positional decoders; no validation | P3-3 |
| 15 | Synthesized `StopEntrance.id` collisions | P3-4 |
| 16 | `Color(hex:)` silently falls back to blue; no tests | P3-5 |
| 17 | Stringly-typed colors; hardcoded Polish/English mix | P3-5, P4-1 |
| 18 | `.unknown` sentinel in `CaseIterable`; unused import | P3-6 |
| 19 | Magic layout constants; fixed 52pt spacer | P4-2 |
| 20 | Duplicate control initializer; global singleton fallback; mixed glass APIs | P4-4 |
| 21 | Hand-drawn map thumbnails | P4-4 (cosmetic, lowest priority) |
| 22 | Missing accessibility labels | P4-3 |
| 23 | City picker ignores documented aliases; trivial `ContentView` | P3-7, P4-1 |
| 24 | Docs claim 66 cities, bbox fetching, pruning; code has 23 and neither | P5-5, P2-1, P2-2 |
| 25 | 170-line city boilerplate | P3-7 |
| 26 | `project.xcproj`, tracked xcuserdata, Swift 5 mode, iOS 27.2 | P5-1, P5-2, P5-3, P5-4 |

---

## 14. Quick-win checklist (first day)

If there is only time for a short session, do these in order:

- [x] P0-2 + P1-1: remove `loadStopsForSelectedCity()` from `init`, call once from `.task`.
- [x] P1-3: stop launching in compact mode.
- [x] P1-2: clear `stops` on city switch.
- [x] P1-4: delete the three dead symbols and the stub assertion.
- [x] P1-6: fix the notch rotation.
- [ ] P3-1: remove `await [` and the force unwrap.
- [ ] P3-5: make invalid hex colors explicit.

These are low-risk, independently mergeable, and remove the most visible symptoms.
