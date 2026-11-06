# ADR-0008 — Marker Density Strategy: Deterministic Spatial Cap (Decision D1)

**Status:** Accepted (2026-11-06)  
**Supersedes:** [ADR-0002](0002-marker-density.md)

## Context

Each stop rendered on the map creates a SwiftUI `Annotation` view. In dense metropolitan networks like Warsaw or Upper Silesia (GZM), thousands of stops may fall within the visible camera viewport. An experimental removal of grid thinning showed that rendering thousands of live SwiftUI annotations causes significant main-thread overhead and frame drops during panning and zooming.

Decision D1 in Refactor Plan 2 evaluated:
1. **Option A (Deterministic Spatial Cap):** Cap rendered viewport markers at a fixed ceiling (250) using deterministic spatial grid thinning.
2. **Option B (Native Clustering):** Migrate SwiftUI `Map` to `MKMapView` via `UIViewRepresentable` and use native `MKClusterAnnotation`.
3. **Option C (Unbounded):** Render all stops in the viewport without a ceiling, relying solely on distance thresholds.

## Decision

Adopt **Option A: Deterministic Spatial Cap** inside `MapViewModel`.

- **Ceiling:** `MapViewModel.maxRenderedStops = 250` strictly bounds the number of annotation views instantiated in SwiftUI.
- **Deterministic Thinning:** When visible stops in the viewport exceed `maxRenderedStops`, a 2D spatial grid is mapped over the visible region. Exactly one representative stop (deterministic selection by smallest `id`) is retained per occupied cell.
- **Deterministic Sort:** The resulting stops are sorted by `id` so consecutive updates do not flicker.
- **Selected Stop Invariant:** The currently selected stop (`selectedStopID`) is always retained in `stops` whenever it lies within the visible viewport, even if grid thinning would have dropped its cell.
- **Session Cache Integrity:** All fetched stops remain cached in `cachedStopsByID`; thinning is purely a presentation-layer projection.

## Alternatives Rejected

- **Option B (Native Clustering via `UIViewRepresentable`):** Rejected because replacing SwiftUI `Map` with `MKMapView` risks breaking pure SwiftUI `.buttonStyle(.glass)`, `MapCompass`, `MapScope`, and native platform behaviors mandated by `AGENTS.md`.
- **Option C (Unbounded Rendering):** Rejected due to unacceptable frame drops and main-thread hitches in dense urban viewports.

## Consequences

- Predictable, bounded memory and rendering footprint across all zoom levels and network densities.
- Preserves 100% native SwiftUI `Map` and Liquid Glass user interface.
- Selection behavior is deterministic and guaranteed not to disappear from the map.

