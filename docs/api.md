# Zbiorkom API Reference

This document provides a complete reference for the `zbiorkom.live` open public transport API (`https://api.zbiorkom.live/api6-open`).

## 1. General Principles & Conventions

- **Base URL:** `https://api.zbiorkom.live/api6-open`
- **Specification:** OpenAPI 3.1 (`GET /api6-open` or `GET /api6-open?city={city}`)
- **Scoping:** Every transit endpoint is prefixed with a `{city}` identifier (e.g. `warsaw`, `krakow`, `wroclaw`, `poznan`, `tricity`, `gzm`, `rybnik`, `pkp`, etc.).
- **Coordinate Order:** All coordinates are `[longitude, latitude]` in WGS 84.
  > [!IMPORTANT]
  > When bridging to MapKit / CoreLocation, note that `CLLocationCoordinate2D` takes `(latitude: point[1], longitude: point[0])`.
- **Timestamps:** Epoch timestamps and duration offsets are expressed in **milliseconds** (`ms`).
- **Data Optimization:** High-frequency endpoints (e.g., `stops`, `positions`, `routes`) return **unkeyed positional JSON arrays (tuples)** rather than JSON objects with key names to minimize network payload sizes.

---

## 2. Endpoints Overview

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api6-open/{city}/stops` | Returns stops for the city, optionally filtered by `?bbox=minLon,minLat,maxLon,maxLat`. |
| `GET` | `/api6-open/{city}/stops/{stopId}` | Real-time departures for a specific stop pole. |
| `GET` | `/api6-open/{city}/positions/{bbox}` | Real-time vehicle positions within the given bounding box. |
| `GET` | `/api6-open/{city}/trips/{tripId}` | Details of a trip, including route path/polyline points and stop sequence. |
| `GET` | `/api6-open/{city}/routes` | List of all routes in the network. |
| `GET` | `/api6-open/{city}/schedule/{route}/{brigade}` | Full day schedule for a vehicle brigade. |

---

## 3. Stops Positional Tuple Schema (`StopTuple`)

Returned from `GET /api6-open/{city}/stops?bbox={minLon},{minLat},{maxLon},{maxLat}`:

```json
{
  "stops": [
    [
      "rybnik-srodmiescie-dworek261-0-j58h8",
      "rybnik",
      "Rybnik Śródmieście Dworek",
      "261/0",
      [18.542289, 50.096472],
      [3],
      145,
      "Chwałowice / Boguszowice",
      [
        ["24", "rybnik", "24", "24", "default", 3, "#215da5"]
      ],
      [
        ["Wejście A", [18.542300, 50.096500]]
      ]
    ]
  ]
}
```

### Positional Index Reference

| Index | Field | Type | Description |
|---|---|---|---|
| `0` | `id` | `String` | Unique stop identifier. Used for departures lookup. |
| `1` | `city` | `String` | City identifier (e.g., `"warsaw"`, `"rybnik"`). |
| `2` | `name` | `String` | Human-readable stop name (e.g. `"Rybnik Śródmieście Dworek"`). |
| `3` | `code` | `String` | Platform or pole number (e.g. `"01"`, `"261/0"`). Empty string if none. |
| `4` | `location` | `[Double]` | Array of two doubles: `[longitude, latitude]`. |
| `5` | `vehicleTypes` | `[Int]` | Array of GTFS route type integers: `0` (tram), `1` (metro), `2` (rail), `3` (bus), `4` (ferry), `6` (cable car), `7` (funicular), `11` (trolleybus), `12` (monorail). |
| `6` | `bearing` | `Int?` | Direction of travel in degrees (`0..360`), or `null` if unknown. |
| `7` | `direction` | `String` | Destination or corridor description (e.g. `"Centrum"`). |
| `8` | `routes` | `[RouteTuple]` | Array of 7-element route tuples serving this stop. |
| `9` | `entrances` | `[EntranceTuple]` | Array of station entrances/exits. |

### `RouteTuple` (7 elements)
- `[0] id: String` — Route identifier (e.g. `"24"`).
- `[1] city: String` — City identifier.
- `[2] name: String` — Short display name (e.g. `"24"`).
- `[3] longName: String` — Descriptive name.
- `[4] agency: String` — Operator identifier (e.g. `"default"`, `"ztm"`).
- `[5] type: Int` — GTFS route type (`RouteType`).
- `[6] color: String` — Hex color string (e.g. `"#215da5"`).

### `EntranceTuple` (2 elements)
- `[0] name: String` — Entrance name.
- `[1] location: [Double]` — `[longitude, latitude]`.

---

## 4. Stop Departures Schema

`GET /api6-open/{city}/stops/{stopId}?limit=20`

Returns keyed JSON:

```json
{
  "departures": [
    {
      "trip": {
        "route": {
          "id": "24",
          "name": "24",
          "agency": "default",
          "type": 3,
          "color": "#215da5"
        },
        "headsign": "Meksyk",
        "brigade": "N-02",
        "shortName": null
      },
      "scheduledDeparture": 1789397160000,
      "delay": 33000,
      "isRealtime": true,
      "isCancelled": false,
      "platform": null
    }
  ]
}
```

- `scheduledDeparture`: Epoch millisecond timestamp of scheduled departure time.
- `delay`: Offset from scheduled departure in milliseconds (`33000` = 33 seconds late, negative values = early).
- `isRealtime`: `true` if tracked by GPS AVL, `false` if scheduled static timetable.
- `isCancelled`: `true` if trip was officially annulled.

---

## 5. Error Schema

Non-200 responses return:

```json
{
  "error": "ERROR_CODE"
}
```

Standard codes:
- `CITY_NOT_FOUND`
- `STOP_NOT_FOUND`
- `INVALID_BBOX`
- `UNKNOWN_ERROR`
