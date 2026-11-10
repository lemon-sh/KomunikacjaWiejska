import Foundation
import MapKit

/// A Web Mercator (slippy-map) tile used as a coverage cell for stop data.
///
/// Stop responses are scale-independent: a bbox returns every stop inside it.
/// All tiles share a single fixed zoom level (Zoom 12) without hierarchy.
struct MapTile: Hashable, Sendable {
    let x: Int
    let y: Int

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Pure tile math shared by the view model and its tests.
///
/// Extreme poles beyond ±85.0511° are clamped to valid Web Mercator bounds.
enum MapTileGrid {
    /// Fixed zoom level for all coverage tiles (Zoom 12 ~6 km × 6 km).
    static let zoom: Int = 12
    private static let maxMercatorLatitude = 85.05112878

    static func visibleTiles(in region: MKCoordinateRegion) -> Set<MapTile> {
        let latitudeDelta = region.span.latitudeDelta
        let longitudeDelta = region.span.longitudeDelta
        guard latitudeDelta.isFinite, longitudeDelta.isFinite,
              latitudeDelta > 0, longitudeDelta > 0
        else { return [] }

        let tileCount = 1 << zoom

        let west = region.center.longitude - longitudeDelta / 2
        let east = region.center.longitude + longitudeDelta / 2
        let north = min(
            maxMercatorLatitude,
            region.center.latitude + latitudeDelta / 2
        )
        let south = max(
            -maxMercatorLatitude,
            region.center.latitude - latitudeDelta / 2
        )
        guard south <= north else { return [] }

        let firstX = Int(floor(tileX(longitude: west)))
        let lastX = Int(floor(tileX(longitude: east)))
        let clampedFirstX = min(max(firstX, 0), tileCount - 1)
        let clampedLastX = min(max(lastX, 0), tileCount - 1)
        guard clampedFirstX <= clampedLastX else { return [] }

        let firstY = Int(floor(tileY(latitude: north)))
        let lastY = Int(floor(tileY(latitude: south)))
        let clampedFirstY = min(max(firstY, 0), tileCount - 1)
        let clampedLastY = min(max(lastY, 0), tileCount - 1)
        guard clampedFirstY <= clampedLastY else { return [] }

        var tiles: Set<MapTile> = []
        tiles.reserveCapacity((clampedLastX - clampedFirstX + 1) * (clampedLastY - clampedFirstY + 1))
        for x in clampedFirstX...clampedLastX {
            for y in clampedFirstY...clampedLastY {
                tiles.insert(MapTile(x: x, y: y))
            }
        }
        return tiles
    }

    /// Smallest bbox containing every tile, usable as a single API request.
    static func boundingBox(covering tiles: Set<MapTile>) -> BoundingBox? {
        guard !tiles.isEmpty else { return nil }

        var minLon = Double.infinity
        var minLat = Double.infinity
        var maxLon = -Double.infinity
        var maxLat = -Double.infinity
        for tile in tiles {
            let bounds = bounds(of: tile)
            minLon = min(minLon, bounds.minLon)
            minLat = min(minLat, bounds.minLat)
            maxLon = max(maxLon, bounds.maxLon)
            maxLat = max(maxLat, bounds.maxLat)
        }
        guard minLon.isFinite, minLat.isFinite, maxLon.isFinite, maxLat.isFinite else {
            return nil
        }
        return BoundingBox(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }

    static func bounds(of tile: MapTile) -> BoundingBox {
        let tileCount = Double(1 << zoom)
        let minLon = Double(tile.x) / tileCount * 360.0 - 180.0
        let maxLon = Double(tile.x + 1) / tileCount * 360.0 - 180.0
        let maxLat = latitude(tileY: Double(tile.y))
        let minLat = latitude(tileY: Double(tile.y + 1))
        return BoundingBox(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }

    static func tileX(longitude: Double) -> Double {
        (longitude + 180.0) / 360.0 * Double(1 << zoom)
    }

    static func tileY(latitude: Double) -> Double {
        let clamped = min(max(latitude, -maxMercatorLatitude), maxMercatorLatitude)
        let radians = clamped * .pi / 180.0
        return (1.0 - log(tan(radians) + 1.0 / cos(radians)) / .pi)
            / 2.0
            * Double(1 << zoom)
    }

    static func latitude(tileY: Double) -> Double {
        let tileCount = Double(1 << zoom)
        let mercator = Double.pi * (1.0 - 2.0 * tileY / tileCount)
        return atan(sinh(mercator)) * 180.0 / Double.pi
    }
}
