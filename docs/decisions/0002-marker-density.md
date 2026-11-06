# ADR-0002 — Marker density strategy: grid thinning (Decision 1D2)

**Status:** Superseded by [ADR-0008](0008-marker-density.md) (2026-11-06)

## Context
SwiftUI `Annotation` is created per stop; large cities can return thousands of
stops for one viewport and drop frames when the map renders them all.

## Historical Decision
Option **A — grid-based thinning inside `MapViewModel`** (MVP), as recorded in the
initial refactor plan:

- `MapViewModel.maxRenderedStops = 250` bounds the rendered marker set.
- Above the bound, the fetched set is thinned deterministically: a square grid
  is laid over the visible region and one representative per occupied cell is
  kept (smallest stop ID wins, output sorted by ID, so repaints don't flicker).
- The full fetched set stays in the view model (selection lookup uses it); only
  `stops` — the thinned array — is rendered.

Rejected for now: Option B (`MKMapView` via `UIViewRepresentable` with native
`MKClusterAnnotation`) — better long-term clustering, but higher regression risk
for Liquid Glass styling and native map controls. The plan's risk register allows
spiking it in a branch later.

## Superseded Note
Superseded by [ADR-0008](0008-marker-density.md) on 2026-11-06, which formally
standardized representative spatial grid thinning with a deterministic 250-stop cap,
selected stop preservation invariant, and integration with `MapConstants`.

## Consequences
- `repainting` binds only to the thinned `stops` array; the camera state is one
  tracked value (`CameraState`) so zoom changes don't re-render every annotation.
- Native behavior preserved: SwiftUI `Map`, `.glass` buttons, native compass.
