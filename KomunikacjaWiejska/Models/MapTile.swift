import Foundation
import MapKit

/// A Web Mercator (slippy-map) tile used as a coverage cell for stop data.
///
/// Stop responses are scale-independent: a bbox returns every stop inside it.
/// All tiles share a single fixed zoom level (Zoom 12) without hierarchy.
struct MapTile: Hashable, Sendable {
    static let zoom: Int = 12

    let x: Int
    let y: Int

    var zoom: Int {
        Self.zoom
    }

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Pure tile math shared by the view model and its tests.
///
/// Note on edge cases: Antimeridian crossing is supported by wrapping X indices.
/// Extreme poles beyond ±85.0511° are clamped to valid Web Mercator bounds.
enum MapTileGrid {
    /// Fixed zoom level for all coverage tiles (Zoom 12 ~6 km × 6 km).
    static let zoom: Int = MapTile.zoom
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

        let firstX = Int(floor(tileX(longitude: west, zoom: zoom)))
        let lastX = Int(floor(tileX(longitude: east, zoom: zoom)))
        let rawXCount = lastX - firstX + 1

        let xTiles: [Int]
        if longitudeDelta >= 360 || rawXCount >= tileCount {
            xTiles = Array(0..<tileCount)
        } else if firstX <= lastX {
            xTiles = (firstX...lastX).map { normalizedX($0, tileCount: tileCount) }
        } else {
            // Viewport crosses the antimeridian.
            let eastSide = (firstX..<tileCount).map { $0 }
            let westSide = (0...lastX).map { $0 }
            xTiles = eastSide + westSide
        }

        let firstY = Int(floor(tileY(latitude: north, zoom: zoom)))
        let lastY = Int(floor(tileY(latitude: south, zoom: zoom)))
        let clampedFirstY = min(max(firstY, 0), tileCount - 1)
        let clampedLastY = min(max(lastY, 0), tileCount - 1)
        guard clampedFirstY <= clampedLastY else { return [] }

        var tiles: Set<MapTile> = []
        tiles.reserveCapacity(xTiles.count * (clampedLastY - clampedFirstY + 1))
        for x in xTiles {
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
        let tileCount = Double(1 << MapTile.zoom)
        let minLon = Double(tile.x) / tileCount * 360.0 - 180.0
        let maxLon = Double(tile.x + 1) / tileCount * 360.0 - 180.0
        let maxLat = latitude(tileY: Double(tile.y), zoom: MapTile.zoom)
        let minLat = latitude(tileY: Double(tile.y + 1), zoom: MapTile.zoom)
        return BoundingBox(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }

    private static func normalizedX(_ x: Int, tileCount: Int) -> Int {
        ((x % tileCount) + tileCount) % tileCount
    }

    static func tileX(longitude: Double, zoom: Int = MapTile.zoom) -> Double {
        (longitude + 180.0) / 360.0 * Double(1 << zoom)
    }

    static func tileY(latitude: Double, zoom: Int = MapTile.zoom) -> Double {
        let clamped = min(max(latitude, -maxMercatorLatitude), maxMercatorLatitude)
        let radians = clamped * .pi / 180.0
        return (1.0 - log(tan(radians) + 1.0 / cos(radians)) / .pi)
            / 2.0
            * Double(1 << zoom)
    }

    static func latitude(tileY: Double, zoom: Int = MapTile.zoom) -> Double {
        let tileCount = Double(1 << zoom)
        let mercator = Double.pi * (1.0 - 2.0 * tileY / tileCount)
        return atan(sinh(mercator)) * 180.0 / Double.pi
    }
}
