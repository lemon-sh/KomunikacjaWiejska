# Architecture Decisions

This document is the central index and executive summary of Architecture Decision Records (ADRs) for **KomunikacjaWiejska**.

Individual, numbered decision records are stored in [`docs/decisions/`](decisions/). When adding or revising architectural decisions, update this central register alongside the corresponding record.

---

## 1. Decision Register

| ADR | Title | Status | Date | Key Decision Summary | Link |
|---|---|---|---|---|---|
| **0001** | Stops Fetch Strategy | Accepted | 2026-11-05 | Debounced (350 ms) viewport `bbox` queries on camera idle; no full-city fetches for large networks. | [ADR-0001](decisions/0001-fetch-strategy.md) |
| **0002** | Marker Density Strategy | Superseded | 2026-11-05 | Superseded by ADR-0008. Initial grid-based thinning in `MapViewModel` capping rendered stops to 250 markers. | [ADR-0002](decisions/0002-marker-density.md) |
| **0003** | Deployment Target iOS 26 | Accepted | 2026-11-05 | Lowered `IPHONEOS_DEPLOYMENT_TARGET` to 26.0 (the minimum for Liquid Glass styling and native MapKit controls). | [ADR-0003](decisions/0003-deployment-target.md) |
| **0004** | Localization Scope | Accepted | 2026-11-05 | Dual Polish (primary) and English support via `Localizable.xcstrings`; stable enum keys; UI-free model layer. | [ADR-0004](decisions/0004-localization.md) |
| **0005** | Swift 6 Concurrency & Isolation | Accepted | 2026-11-05 | Strict Swift 6 mode with `MainActor` default; explicit `nonisolated` for cross-actor value types and DTO decoders. | [ADR-0005](decisions/0005-swift6-concurrency.md) |
| **0006** | Toolchain & JSON Project Format | Accepted | 2026-11-05 | Xcode 27.2+ JSON `project.xcproj` format enforced via `scripts/check-toolchain.sh`; committed shared scheme. | [ADR-0006](decisions/0006-toolchain.md) |
| **0007** | Session Tile Cache for Stops | Accepted | 2026-11-05 | Session-only flat Zoom 12 Web Mercator tile cache per city; union bbox fetching; no artificial TTL/LRU eviction. | [ADR-0007](decisions/0007-tile-cache.md) |
| **0008** | Marker Density Strategy: Deterministic Spatial Cap | Accepted | 2026-11-06 | Deterministic spatial cap in `MapViewModel` capping rendered stops to 250 markers with selected stop preservation. | [ADR-0008](decisions/0008-marker-density.md) |

---

## 2. Executive Summaries

### [ADR-0001: Stops Fetch Strategy (Viewport Bbox)](decisions/0001-fetch-strategy.md)
- **Problem:** Poland's metropolitan networks (e.g. Warsaw, GZM) have tens of thousands of transit poles. Fetching an entire network at launch causes high latency, excessive memory consumption, and sluggish map rendering.
- **Decision:** Trigger bounded bounding-box queries (`{city}/stops?bbox=minLon,minLat,maxLon,maxLat`) via `.onMapCameraChange(frequency: .onEnd)` debounced at 350 ms in `MapViewModel`.
- **Alternatives Rejected:** Full-city prefetching on city switch (unbounded data transfer on cellular networks and excessive memory overhead).
- **Outcome:** Predictable memory footprint and instant responsiveness, supported by session tile caching.

### [ADR-0002: Marker Density Strategy (Grid Thinning)](decisions/0002-marker-density.md)
- **Problem:** SwiftUI Map annotations instantiated per stop can overwhelm the main thread and drop frames in dense viewports containing thousands of poles.
- **Decision:** Cap rendered annotations at `maxRenderedStops = 250` using deterministic grid-based spatial thinning in `MapViewModel`. The cell with the lowest stop ID represents each slot to eliminate marker flicker during repaints. Full stop details remain cached in the view model for selection.
- **Alternatives Rejected:** Direct `MKMapView` representable with native `MKClusterAnnotation` (deferred to maintain pure SwiftUI Liquid Glass styling and standard MapKit controls).
- **Outcome:** Superseded by ADR-0008.

### [ADR-0003: Deployment Target Lowered to iOS 26](decisions/0003-deployment-target.md)
- **Problem:** The repository previously defaulted to iOS 27.2, excluding most real-world devices despite all required features (`.buttonStyle(.glass)`, `GlassEffectContainer`, `MapCompass`) existing in iOS 26.0.
- **Decision:** Set `IPHONEOS_DEPLOYMENT_TARGET = 26.0` across the project and test targets.
- **Alternatives Rejected:** Retaining 27.2 (needlessly restricted distribution) or lowering to iOS 25 (which would require fragile fallbacks for Liquid Glass APIs).
- **Outcome:** Broad hardware compatibility while maintaining 100% native Liquid Glass UI.

### [ADR-0004: Localization Scope](decisions/0004-localization.md)
- **Problem:** User interface strings were a mix of Polish literals and English technical identifiers.
- **Decision:** Support both Polish (`pl`, primary) and English (`en`) via `Localizable.xcstrings`. Keep domain identifiers and raw values locale-independent, and isolate UI presentation copy to `RouteType+UI.swift`.
- **Alternatives Rejected:** Polish-only strings or code-level conditional translations.
- **Outcome:** Clean, localized presentation compliant with international App Store requirements.

### [ADR-0005: Swift 6 Concurrency & Isolation](decisions/0005-swift6-concurrency.md)
- **Problem:** Strict concurrency checking produced warnings under Swift 5 and broke under Swift 6 when passing models and responses across actors.
- **Decision:** Adopt Swift 6 language mode with complete strict concurrency. Retain `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for views and view models, isolate `ZbiorkomAPIClient` to an actor, and mark purely immutable DTOs and value types (`BoundingBox`, `StopsResponse`) as `nonisolated` and `Sendable`.
- **Alternatives Rejected:** Silencing warnings via `@preconcurrency` imports or disabling strict checking.
- **Outcome:** 100% compiler-verified data-race safety without runtime concurrency overhead.

### [ADR-0006: Toolchain & JSON Project Format](decisions/0006-toolchain.md)
- **Problem:** Xcode 27.2 uses the JSON `project.xcproj` format rather than legacy `project.pbxproj`, breaking compatibility with older Xcode builds.
- **Decision:** Standardize on Xcode 27.2+ as the prerequisite toolchain, enforce via `scripts/check-toolchain.sh`, and track shared schemes in version control while ignoring user data (`xcuserdata`).
- **Alternatives Rejected:** Reverting to the legacy pbxproj format.
- **Outcome:** Clean, human-readable, merge-conflict-resistant project metadata for modern Xcode development.

### [ADR-0007: Session Tile Cache for Stops](decisions/0007-tile-cache.md)
- **Problem:** Keying cache entries by exact coordinate bounding boxes caused constant cache misses during small pans and zooms, resulting in repeated network calls and flashing markers.
- **Decision:** Implement a session-only, per-city tile cache using flat Zoom 12 Web Mercator tile keys (`MapTile.zoom = 12`). Viewports request missing tiles via union bboxes without multi-level cache hierarchies, and results are merged by stop ID.
- **Alternatives Rejected:** Bounding-box cache with 10-minute TTL and LRU eviction (prone to cache misses and unnecessary cache invalidation).
- **Outcome:** Smooth zoom-in rendering, zero redundant downloads for previously visited neighborhoods, and automatic reset on city switch.

### [ADR-0008: Marker Density Strategy: Deterministic Spatial Cap](decisions/0008-marker-density.md)
- **Problem:** Rendering thousands of live SwiftUI annotations in dense metropolitan regions causes frame drops and main-thread hitches.
- **Decision:** Formally re-adopt a deterministic spatial representative cap (`maxRenderedStops = 250`) in `MapViewModel`. Visible stops exceeding the ceiling are thinned via a 2D spatial grid, retaining one representative per cell and always preserving the currently selected stop when within the viewport.
- **Alternatives Rejected:** `UIViewRepresentable` wrapping `MKMapView` (violates native Liquid Glass / MapKit control constraints) or unbounded annotations.
- **Outcome:** 60/120 fps panning and zooming performance across all cities with deterministic annotation updates.

### [ADR-0008: Marker Density Strategy: Deterministic Spatial Cap](decisions/0008-marker-density.md)
- **Problem:** Rendering thousands of live SwiftUI annotations in dense metropolitan regions causes frame drops and main-thread hitches.
- **Decision:** Formally re-adopt a deterministic spatial representative cap (`maxRenderedStops = 250`) in `MapViewModel`. Visible stops exceeding the ceiling are thinned via a 2D spatial grid, retaining one representative per cell and always preserving the currently selected stop when within the viewport.
- **Alternatives Rejected:** `UIViewRepresentable` wrapping `MKMapView` (violates native Liquid Glass / MapKit control constraints) or unbounded annotations.
- **Outcome:** 60/120 fps panning and zooming performance across all cities with deterministic annotation updates.

---

## 3. Contributing & Adding New Decisions

When proposing an architectural change or recording a new design decision:

1. **Create an ADR file:** Name it `docs/decisions/{NUMBER}-{slug}.md` (e.g. `0008-departure-boards.md`) following the four-digit zero-padded numbering.
2. **Follow the ADR template:**
   ```markdown
   # ADR-{NUMBER} — {Title}

   **Status:** Proposed | Accepted | Deprecated | Superseded by ADR-{X} ({YYYY-MM-DD})

   ## Context
   What problem are we trying to solve? What are the constraints, trade-offs, and background?

   ## Decision
   What is the specific choice? How does it fit into the architecture?

   ## Alternatives Rejected
   What alternatives were considered and why were they rejected?

   ## Consequences
   What are the positive, negative, and neutral impacts of this decision?
   ```
3. **Register the decision:** Add a row to the [Decision Register](#1-decision-register) above and add a concise summary in [Executive Summaries](#2-executive-summaries).
4. **Update references:** Ensure [AGENTS.md](../AGENTS.md) and relevant documentation reflect the updated state.

