# ADR-0002 — Marker density strategy: grid thinning (Decision D2)

**Status:** Accepted (2026-11-05)

## Context
SwiftUI `Annotation` is created per stop; large cities can return thousands of
stops for one viewport and drop frames when the map renders them all.

## Decision
Option **A — grid-based thinning inside `MapViewModel`** (MVP), as recorded in the
refactor plan §11:

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

## Consequences
- `repainting` binds only to the thinned `stops` array; the camera state is one
  tracked value (`CameraState`) so zoom changes don't re-render every annotation.
- Native behavior preserved: SwiftUI `Map`, `.glass` buttons, native compass.
