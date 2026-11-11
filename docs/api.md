# `api.zbiorkom.live/api6` Specification & Positional Schema

**KomunikacjaWiejska** communicates directly with `https://api.zbiorkom.live/api6` over HTTPS (`URLSession`) and Server-Sent Events (`SSEFrameParser` on top of `URLSession.bytes(for:)`).

> [!IMPORTANT]
> **Coordinate Order:** All coordinate pairs in `/api6` follow GeoJSON `[longitude, latitude]` order (`lon = [0]`, `lat = [1]`), decoded into `CLLocationCoordinate2D(latitude: lat, longitude: lon)`.
> **Path Encoding:** Each path segment is strictly percent-encoded (`alphanumerics` + `"-._~"`), matching JavaScript `encodeURIComponent` so colons/slashes in vehicle and trip IDs (such as `3:MM831` -> `3%3AMM831`) are preserved cleanly.

---

## 1. Endpoints

| Kind | Method / Protocol | Path | Consumer |
|---|---|---|---|
| **City Catalog** | `GET` (JSON) | `/api6` | `ZbiorkomAPIClient.fetchCities()` |
| **Vehicle Metadata** | `GET` (JSON) | `/api6/{city}/vehicles/vehicle/{vehicleId}` | `ZbiorkomAPIClient.fetchVehicleMetadata(city:vehicleId:)` |
| **Map Features** | `GET` (`text/event-stream`) | `/api6/{city}/mapFeatures/{zoom}/{minLon},{minLat},{maxLon},{maxLat}/stream` | `ZbiorkomAPIClient.streamMapFeatures(city:zoom:bbox:)` |
| **Stop Departures** | `GET` (`text/event-stream`) | `/api6/{city}/stops/{stopId}/stream?limit=21` | `ZbiorkomAPIClient.streamStopDepartures(city:stopId:limit:)` |
| **Vehicle / Trip Live** | `GET` (`text/event-stream`) | `/api6/{city}/positions/{vehicleId}/stream` | `ZbiorkomAPIClient.streamVehiclePosition(city:vehicleId:)` |
| **Scheduled Trip** | `GET` (`text/event-stream`) | `/api6/{city}/trips/{tripId}/stream` | `ZbiorkomAPIClient.streamTrip(city:tripId:)` |

SSE streams emit `event: initial` on connection open followed by periodic `event: message` pushes roughly every 10 seconds (`:00, :10, :20, ...`). Server error frames arrive under `event: errorCode`.

---

## 2. REST Schemas

### `GET /api6` (`CitiesResponse`)
```json
{
  "hash": "3pmo7n8olz3ua",
  "shouldUpdate": true,
  "cities": [
    {
      "id": "krakow",
      "name": "Kraków",
      "description": "...",
      "category": "lesserPoland",
      "location": [19.94781, 50.06865],
      "timezone": "Europe/Warsaw",
      "virtual": false,
      "agencies": {
        "default": { "id": "default", "name": "ZTP Kraków", "faresUrl": "...", "icon": "<path .../>" }
      }
    }
  ]
}
```
Entries with `virtual: true` (`pkp`, `mld`, `lka`, `flixbus`, `digitraffic`) are excluded from `CityPickerSheet` and region suggestions, while preserved for cross-city stream URL routing (`stop.city`, `vehicle.city`, `trip.city`).

### `GET /api6/{city}/vehicles/vehicle/{vehicleId}` (`VehicleMetadata`)
Positional 5-tuple: `[id, model, prodYear, carrier, imageHash]`.

---

## 3. Positional Tuple Reference

### `StopRoute` (`RouteTuple`)
`[0: id, 1: city, 2: name, 3: longName, 4: agency, 5: type (GTFS Int), 6: color (hex with/without #)]`

### `Stop`
- **`mapFeatures` `initial`** emits 7-element tuples:
  `[0: id, 1: city, 2: name, 3: code, 4: [lon, lat], 5: types ([Int]), 6: bearing?]`
- **`stops/{id}/stream` `initial`** emits full 10-element tuples:
  `[0..6]` plus `[7: direction?, 8: [StopRoute], 9: [[entranceName, [lon, lat]]]]`

`Stop.hasFullMetadata` tracks whether the stop has been hydrated from a 10-element metadata tuple.

### `DotVehicle` & `MapFeaturesUpdate`
- **`DotVehicle`**: `[0: colorHex, 1: [lon, lat]]` (returned in `dots` when zoomed out `< ~15`).
- **`MapFeaturesUpdate`**: `{"positions": [VehiclePosition], "dots": [DotVehicle], "bbox": [minLon, minLat, maxLon, maxLat]?, "traffic": ...}`.

### `VehiclePosition`
- **6-tuple (`mapFeatures`, `StopDeparture`)**:
  `[0: id, 1: city, 2: StopRoute, 3: brigade, 4: [lon, lat], 5: bearing?]`
- **9-tuple (`positions/{id}/stream`)**:
  `[0..5]` plus `[6: lastPingMs?, 7: tripId?, 8: percentTraveled?]`

### `StopDeparture` & `StopTimeUpdate`
- **`StopDeparture`**: `[0: TripInfo, 1: VehiclePosition?, 2: departure StopTimeUpdate, 3: destination StopTimeUpdate?]`
- **`StopTimeUpdate`**: `[0: scheduledMs, 1: delayMs?, 2: DepartureStatus (0=Scheduled, 1=OnTrip, 2=OnPreviousTrip, 3=Cancelled), 3: platform?, ...]`

### `TripInitial`, `Itinerary` & `TripUpdate`
- **`TripInfo`**: `[0: id, 1: city, 2: StopRoute, 3: headsign, 4: brigade?, 5: shortName?, 6: [[key, value]]?, ...]`
- **`Itinerary`**: `[0: [ItineraryStop], 1: encodedPolyline6, ...]` — polylines use factor **`1e6`** (`PolylineDecoder`).
- **`ItineraryStop`**: `[0: Stop, 1: alightBitmask (1=regular, 2=forbidden, 4=onDemand, 8=isLastStop), 2: distanceMeters?, 3: platform?, ...]`
- **`TripStopUpdate`**: `[0: arrival StopTimeUpdate, 1: departure StopTimeUpdate, 2: platform?, 3: track?, 4: [TripAlert]?]`
- **`TripAlert`**: `[0: title, 1: description, 2: url?, 3: publishedAtMs?, 4: activeFromMs?, 5: activeUntilMs?, 6: language?, 7: detected?]`

---

## 4. Supported `RouteType` Values

| Value | Case | SF Symbol | Default Hex |
|---:|---|---|---|
| `0` | `.tram` | `tram.fill` | `#E53935` |
| `1` | `.subway` | `tram.fill.tunnel` | `#1E88E5` |
| `2` | `.rail` | `train.side.front.car` | `#43A047` |
| `3` | `.bus` | `bus.fill` | `#FB8C00` |
| `4` | `.ferry` | `ferry.fill` | `#00ACC1` |
| `6` | `.aerialLift` | `cablecar.fill` | `#546E7A` |
| `7` | `.funicular` | `cablecar` | `#546E7A` |
| `11` | `.trolleybus` | `bus.doubledecker.fill` | `#8E24AA` |
| `12` | `.monorail` | `train.side.middle.car` | `#546E7A` |
| `-1` / other | `.unknown` | `questionmark.circle.fill` | `#757575` |
