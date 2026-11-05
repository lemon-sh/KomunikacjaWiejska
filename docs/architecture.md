# Architecture Guide

This document describes the software architecture, state flow, MapKit integration, and future expansion roadmap for the `KomunikacjaWiejska` native iOS app.

---

## 1. Architectural Principles

1. **Native-First Design:**
   - Pure Apple frameworks: `SwiftUI`, `MapKit`, `CoreLocation`, `Observation`, and `Foundation`.
   - Prefer Apple HIG idioms: Liquid Glass via native `.buttonStyle(.glass)` / `glassEffect` / `GlassEffectContainer`, SF Symbols, native MapKit controls (`MapCompass`), and standard bottom sheets (`.presentationDetents`).
   - The app never re-implements platform chrome (compass animations, glass buttons, map gestures).
2. **Observation & Swift Concurrency:**
   - View models use the Swift `@Observable` macro and `@MainActor`.
   - No Combine pipelines or `ObservableObject` classes.
   - Network interactions are actor-isolated (`ZbiorkomAPIClient: actor`) with `async`/`await`.
   - The app builds in **Swift 6 language mode** with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure value types used across actors (`BoundingBox`, model types, `StopsProviding`) are explicitly `nonisolated`; no blanket `@preconcurrency` escapes.
3. **Optimized Map Performance:**
   - Public transit networks in metropolitan areas contain tens of thousands of stop poles.
   - Stops are fetched **per visible viewport**: `.onMapCameraChange(frequency: .onEnd)` debounces camera changes (350 ms) and `MapViewModel` passes the viewport bounding box (`minLon,minLat,maxLon,maxLat`) to the backend.
   - Viewport results are cached in memory with a 10-minute TTL and LRU eviction (8 entries); failures and empty results are never cached.
   - When a viewport returns more than 250 stops, `MapViewModel` thins them deterministically (one representative per grid cell) before rendering.
   - Camera metrics are grouped into one `CameraState` value, so annotations re-render only when the visible/thinned stop set changes.
4. **Localization & Accessibility:**
   - User-facing copy lives in `Resources/Localizable.xcstrings` with Polish (`pl`) and English (`en`) translations.
   - `MapMode` and `RouteType` keep locale-independent identifiers/raw values; display names are localized in the UI layer.
   - Icon-only controls have accessibility labels, markers combine into one element, and the selected stop/route type is announced.

---

## 2. Component Hierarchy & Flow

```mermaid
flowchart TD
    App["KomunikacjaWiejskaApp"] --> Content["ContentView"]
    Content --> MapView["TransitMapView (SwiftUI Map)"]
    MapView --> TopBar["Top Chrome (City Picker, Refresh, Status/Retry)"]
    MapView --> Annotations["Map Annotations (ForEach Stop)"]
    Annotations --> MarkerView["StopMarkerView (Icon + Bearing Arrow)"]
    MapView --> DetailSheet["StopDetailSheet (.sheet(item: selectedStop))"]
    DetailSheet --> RouteBadges["RouteBadgeView (Pill badge per StopRoute)"]
    MapView --> CitySheet["CityPickerSheet (Searchable City List)"]
    MapView --> Controls["MapControlsComboView (Map mode, Location)"]

    TopBar --> Localized["Localizable.xcstrings (pl/en)"]
    Annotations --> Localized
    DetailSheet --> Localized

    MapView <-->|Binds to| ViewModel["MapViewModel (@Observable @MainActor)"]
    ViewModel -->|BBox Query| Client["ZbiorkomAPIClient (actor)"]
    Client -->|REST HTTP| API["https://api.zbiorkom.live/api6-open"]
```

---

## 3. Key Files & Responsibilities

### Models (`KomunikacjaWiejska/Models/`)
- [`RouteType.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Models/RouteType.swift):
  - GTFS route types (`tram`, `subway`, `rail`, `bus`, `ferry`, `aerialLift`, `funicular`, `trolleybus`, `monorail`).
  - Maps route types to SF Symbols (`tram.fill`, `bus.fill`, etc.) and brand colors.
- [`BoundingBox.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Models/BoundingBox.swift):
  - Calculates `minLon,minLat,maxLon,maxLat` from an `MKCoordinateRegion` for API requests.
- [`Stop.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Models/Stop.swift):
  - `Stop`, `StopRoute`, `StopEntrance` models.
  - Implements custom `Decodable` parsing of the unkeyed positional arrays (`unkeyedContainer()`).
- [`City.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Models/City.swift):
  - Static catalog of supported Polish cities, default coordinates, and map spans.

### Networking (`KomunikacjaWiejska/Services/`)
- [`ZbiorkomAPIClient.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Services/ZbiorkomAPIClient.swift):
  - Actor managing `URLSession` communication with `api.zbiorkom.live`.
  - Encapsulates error parsing (`ZbiorkomAPIError`).
- [`StopsProviding.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Services/StopsProviding.swift):
  - Injectable abstraction over the stops data source; `ZbiorkomAPIClient` conforms so `MapViewModel` can be built with a stub in tests.

- [`LocationManager.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Services/LocationManager.swift):
  - Wraps `CLLocationManager`, derives a testable authorization state, resolves one-shot fixes asynchronously (waiting for the permission prompt when needed), and logs failures.

### Extensions (`KomunikacjaWiejska/Extensions/`)
- [`Color+Hex.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Extensions/Color+Hex.swift):
  - Failable `Color(hex:)` for 3-, 6-, and 8-digit (ARGB) strings, plus an explicit-fallback convenience.
- [`RouteType+UI.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Extensions/RouteType+UI.swift):
  - SwiftUI color and localized display name for `RouteType`; keeps the model UI-free.

### Resources (`KomunikacjaWiejska/Resources/`)
- `Localizable.xcstrings` — Polish and English copy (map chrome, errors, stop sheet, accessibility).
- `InfoPlist.xcstrings` — localized system permission prompts (location usage description).
- `cities.json` — the bundled 66-network city catalog.

### Presentation (`KomunikacjaWiejska/ViewModels/` & `Views/`)
- [`MapViewModel.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/ViewModels/MapViewModel.swift):
  - Central `@Observable` state holder. Manages camera position, selected city, visible stops, active stop selection, loading phase (`initial` / `refresh` / `citySwitch`), localized errors, and cancellation of pending network tasks.
- [`TransitMapView.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Views/TransitMapView.swift):
  - Root map screen with MapKit standard layer (POI disabled for clarity), safe-area-aware top chrome, a retryable status capsule, and a visible refresh control.
- `DesignTokens.swift` — shared spacing, control, and marker metrics.
- [`StopMarkerView.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Views/StopMarkerView.swift):
  - Circular transit badge showing transit icon and a triangle notch rotated to the stop's `bearing`.
- [`StopDetailSheet.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Views/StopDetailSheet.swift):
  - Non-blocking bottom sheet showing platform number, direction, and route chips.
- [`CityPickerSheet.swift`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejska/Views/CityPickerSheet.swift):
  - Searchable list of Polish cities allowing the user to jump between transit networks.

---

## 4. Future Roadmap

1. **Stop Departures (Milestone 2):**
   - Query `GET /api6-open/{city}/stops/{stopId}` when a stop is selected.
   - Display real-time departure countdowns, delays in minutes, and cancellations.
2. **Live Vehicle Positions (Milestone 3):**
   - Poll `GET /api6-open/{city}/positions/{bbox}` periodically (e.g., every 3-5s).
   - Render animated vehicle markers on the map with route numbers and bearings.
3. **Trip Route Polyline & Vehicle Trace (Milestone 4):**
   - Query `GET /api6-open/{city}/trips/{tripId}` or route geometries to draw transit lines using `MapPolyline`.
