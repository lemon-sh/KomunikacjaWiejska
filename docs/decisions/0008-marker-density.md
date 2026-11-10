# ADR-0008 — Marker Density Strategy: Deterministic Spatial Cap & Buffered Background Thinning (Decision 2D1)

**Status:** Accepted (2026-11-06, updated 2026-11-10)  
**Supersedes:** [ADR-0002](0002-marker-density.md)

## Context

Each stop rendered on the map creates a SwiftUI `Annotation` view. In dense metropolitan networks like Warsaw or Upper Silesia (GZM), thousands of stops may fall within the visible camera viewport. An experimental removal of grid thinning showed that rendering thousands of live SwiftUI annotations causes significant main-thread overhead and frame drops during panning and zooming.

Furthermore, strictly bounding thinning queries to the exact visible viewport caused continuous annotation churn: any minor pan shifted the bounding box, forcing MapKit to tear down and instantiate new `MKAnnotationView` / `UIHostingController` instances, resulting in visible map stutter when panning while stops were visible. Synchronous grid thinning and array sorting on the main actor exacerbated these hitches.

Decision 2D1 in Refactor Plan 2 evaluated:
1. **Option A (Deterministic Spatial Cap with Buffered Background Thinning):** Cap rendered viewport markers at a fixed ceiling (250) using deterministic spatial grid thinning computed asynchronously in a background Task, with an expanded viewport buffer (hysteresis) to prevent continuous annotation recreation during panning.
2. **Option B (Native Clustering):** Migrate SwiftUI `Map` to `MKMapView` via `UIViewRepresentable` and use native `MKClusterAnnotation`.
3. **Option C (Unbounded):** Render all stops in the viewport without a ceiling, relying solely on distance thresholds.

## Decision

Adopt **Option A: Deterministic Spatial Cap with Buffered Background Thinning** inside `MapViewModel`.

- **Ceiling:** `MapViewModel.maxRenderedStops = 250` strictly bounds the number of annotation views instantiated in SwiftUI.
- **Deterministic Thinning:** When visible stops in the viewport exceed `maxRenderedStops`, a 2D spatial grid is mapped over the region. Exactly one representative stop (deterministic selection by smallest `id`) is retained per occupied cell.
- **Deterministic Sort:** The resulting stops are sorted by `id` so consecutive updates do not flicker.
- **Selected Stop Invariant:** The currently selected stop (`selectedStopID`) is always retained in `stops` whenever it lies within the visible viewport, even if grid thinning would have dropped its cell.
- **Buffered Viewport Hysteresis:** Query bounds are expanded by a 50% margin (`viewportBufferFactor = 1.50`). Re-thinning is skipped while the user pans within the buffered boundary and zoom remains stable (`zoomChangeRatioThreshold = 0.20`), eliminating continuous annotation churning during pan gestures.
- **Asynchronous Background Thinning:** Filtering, grid bucketing, and sorting are offloaded to background tasks (`Task.detached(priority: .userInitiated)`) using cooperative cancellation and generation tracking (`thinningGeneration`), ensuring the main thread is never blocked.
- **Incremental Contiguous Array Cache:** Stop data is maintained in a contiguous `cachedStops: [Stop]` array with an $O(1)$ `stopIndexByID: [String: Int]` index map. Passing cached stops to background tasks utilizes Swift's copy-on-write without allocating memory or iterating dictionary values on the main actor.
- **Fetch Settlement Ordering:** Network tile fetches complete stop thinning before marking the request state as loaded, guaranteeing tests and UI observe consistent stops without race conditions.
- **Session Cache Integrity:** All fetched stops remain cached in the session store; thinning is purely a presentation-layer projection.

## Alternatives Rejected

- **Option B (Native Clustering via `UIViewRepresentable`):** Rejected because replacing SwiftUI `Map` with `MKMapView` risks breaking pure SwiftUI `.buttonStyle(.glass)`, `MapCompass`, `MapScope`, and native platform behaviors mandated by `AGENTS.md`.
- **Option C (Unbounded Rendering):** Rejected due to unacceptable frame drops and main-thread hitches in dense urban viewports.

## Consequences

- Predictable, bounded memory and rendering footprint across all zoom levels and network densities.
- Butter-smooth panning: zero annotation recreation when moving within the buffered area, and zero main thread hitches during camera updates.
- Preserves 100% native SwiftUI `Map` and Liquid Glass user interface.
- Selection behavior is deterministic and guaranteed not to disappear from the map.

