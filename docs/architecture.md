# Architecture & Design Guide

**KomunikacjaWiejska** is a native iOS transit visualizer built with pure Apple frameworks (`SwiftUI`, `MapKit`, `CoreLocation`, `Observation`, Swift 6 concurrency) connected to `https://api.zbiorkom.live/api6` (see [`ADR-0009`](decisions/0009-api6-sse-streaming.md)).

---

## 1. High-Level Data & Streaming Architecture

1. **Dynamic City Bootstrap (`GET /api6`)**:
   - On launch (`MapViewModel.start()`), `ZbiorkomAPIClient.fetchCities()` loads the live catalog (`City` records including `location`, `timezone`, `agencies`, and `virtual` flags) directly from `GET /api6` without any bundled offline city catalog. If loading fails, `MapViewModel` enters a retryable error state until `GET /api6` succeeds.
2. **Viewport SSE Stream (`mapFeatures/{zoom}/{bbox}/stream`)**:
   - MapKit camera changes (`onMapCameraChange(frequency: .onEnd)`) debounce (`350 ms` via `MapConstants.cameraDebounce`), compute clamped `BoundingBox` and Web Mercator `zoom` (`BoundingBox.webMercatorZoom(viewportWidth:)`), and open a live SSE connection (`SSEFrameParser` over `URLSession.bytes(for:)`).
   - Zoomed-out views emit colored `dots` (`DotMarkerView`); street-level views emit 7-tuple `stops` (`StopMarkerView`) and 6-tuple live `positions` (`VehicleMarkerView`).
3. **Selection Isolation, Navigation Stack & Detail Streams**:
   - **Selecting a Stop (`selection = .stop(id)`)** opens `stops/{stop.city}/stops/{stop.id}/stream` (routing cleanly via `stop.city` for cross-city operators), hydrates missing 10-tuple fields (`direction`, `routes`, `entrances`), isolates surrounding map markers to the stop, its entrances, and active departure vehicles, and streams `StopDeparture` rows.
   - **Tapping a Departure -> Trip Sheet (`openDeparture(_:)`)** saves the originating `Stop` so `<` Back (`navigateBackToStop()`) returns cleanly to `StopDetailSheet`, transitions inside the single active `.sheet(isPresented:)` container to `VehicleDetailSheet`, opens `positions/{city}/{vehicleId}/stream` (plus `vehicles/vehicle/{vehicleId}`) or `trips/{city}/{tripId}/stream` for scheduled trips without assigned vehicles, renders the `1e6` Google-encoded `MapPolyline` and `ItineraryStop` dots on the map, and optionally tracks live vehicle coordinates (`isFollowingVehicle`).
4. **App Background Lifecycle (`scenePhase`)**:
   - Moving off `.active` starts a `45 s` background teardown timer (`sseBackgroundDisconnectDelay`); returning to `.active` reopens streams automatically when disconnected or stale (`>= 10 s` elapsed).

---

## 2. Project File Map

```text
KomunikacjaWiejska/
├── KomunikacjaWiejskaApp.swift         # App entry point (skips map under XCTest)
├── Models/
│   ├── BoundingBox.swift                # Clamp/containment + coordinate bounds
│   ├── City.swift                       # CitiesResponse, Agency, City catalog model
│   ├── RouteType.swift                  # GTFS route type enum
│   ├── Stop.swift                       # StopRoute (7-tuple), StopEntrance, 7/10-tuple Stop
│   ├── TripModels.swift                 # MapFeatures*, StopDeparture, StopTimeUpdate, Itinerary, TripAlert, VehicleMetadata
│   ├── TupleDecoding.swift              # Nonisolated TupleReader, CoordinatePair, Web Mercator zoom
│   └── VehiclePosition.swift            # DotVehicle (2-tuple), VehiclePosition (6/9-tuple)
├── Services/
│   ├── CameraPersistence.swift          # UserDefaults + InMemory store protocols
│   ├── LocationManager.swift            # CoreLocation state wrapper
│   ├── LocationProviding.swift          # Location protocol
│   ├── SSEStreamParser.swift            # Byte-level SSE frame parser (event:, data:, retry:, comments)
│   ├── StopsProviding.swift             # TransitDataProviding async/SSE protocol
│   └── ZbiorkomAPIClient.swift          # Actor HTTP + SSE client for https://api.zbiorkom.live/api6
├── ViewModels/
│   └── MapViewModel.swift               # @Observable @MainActor state, streams, selection stack & isolation
├── Views/
│   ├── CityPickerSheet.swift            # Searchable non-virtual city switcher
│   ├── DesignTokens.swift               # Shared layout metrics & sheet detents
│   ├── MapControlsComboView.swift       # Native Liquid Glass map style + location controls
│   ├── StopDetailSheet.swift            # Hydrated stop header + live departures board
│   ├── StopMarkerView.swift             # Circle / Metro-Rail rounded-square badge + bearing pointer
│   ├── TransitMapView.swift             # MapKit canvas, polyline, dots, stops, vehicles & sheet coordinator
│   ├── VehicleDetailSheet.swift         # Full itinerary timeline, percentTraveled track, alerts & metadata
│   └── VehicleMarkerView.swift          # Rounded route badge + DotMarkerView
├── Utilities/
│   ├── MapConstants.swift               # SSE timing, retry, debounce & marker size constants
│   ├── PolylineDecoder.swift            # Pure Swift 1e6 Google polyline decoder
│   └── TransitTimeFormatting.swift      # Timezone-aware HH:mm clocks, countdowns, ping age & delay states
├── Extensions/
│   ├── Color+Hex.swift                  # 3/6/8-digit hex parsing (with or without #) & WCAG contrast
│   ├── Logger+Categories.swift          # Subsystem os.Logger categories
│   ├── RouteType+UI.swift               # SF Symbols, localized names, default colors
│   └── VehiclePosition+UI.swift         # Route/vehicle/dot display colors
└── Resources/
    └── Localizable.xcstrings            # Polish & English localized strings
```

---

## 3. Hermetic Testing Architecture

`KomunikacjaWiejskaTests` uses Swift `Testing` (`@Suite`, `@Test`, `#expect`) with zero live network access:
- `MockURLProtocol` tests `ZbiorkomAPIClient` HTTP requests, percent-encoding, error paths, and multi-event SSE streams (`SSEFrameParser`).
- `StubStopsProvider` (`TransitDataProviding`) drives deterministic `AsyncThrowingStream` events into `MapViewModel`.
- `InMemoryCameraPersistenceStore` isolates persisted city and camera restoration in tests.
