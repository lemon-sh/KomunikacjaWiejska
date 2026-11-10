import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import MapKit
import Testing

@Suite("MapTile & Grid Tests")
@MainActor
struct MapTileTests {
    @Test("BoundingBox calculations and query string")
    func testBoundingBox() {
        let bbox = BoundingBox(minLon: 21.0, minLat: 52.2, maxLon: 21.1, maxLat: 52.3)
        #expect(bbox.minLon == 21.0)
        #expect(bbox.minLat == 52.2)
        #expect(bbox.maxLon == 21.1)
        #expect(bbox.maxLat == 52.3)
        #expect(bbox.queryValue == "21.000000,52.200000,21.100000,52.300000")

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.25, longitude: 21.05),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let converted = BoundingBox(region: region)
        #expect(converted != nil)
        #expect(abs(converted!.minLon - 21.0) < 0.0001)
        #expect(abs(converted!.maxLon - 21.1) < 0.0001)
        #expect(abs(converted!.minLat - 52.2) < 0.0001)
        #expect(abs(converted!.maxLat - 52.3) < 0.0001)
    }

    @Test("Tile grid covers the viewport and stays within a useful zoom range")
    func testTileGridCoverage() throws {
        let warsawRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: City.warsaw.defaultLatitudeDelta,
                longitudeDelta: City.warsaw.defaultLongitudeDelta
            )
        )
        let tiles = MapTileGrid.visibleTiles(in: warsawRegion)
        #expect(!tiles.isEmpty)
        #expect(tiles.count <= 25)

        for tile in tiles {
            #expect(tile.x >= 0)
            #expect(tile.y >= 0)
        }

        let coveringBBox = try #require(MapTileGrid.boundingBox(covering: tiles))
        #expect(coveringBBox.minLon <= City.warsaw.coordinate.longitude)
        #expect(coveringBBox.maxLon >= City.warsaw.coordinate.longitude)
        #expect(coveringBBox.minLat <= City.warsaw.coordinate.latitude)
        #expect(coveringBBox.maxLat >= City.warsaw.coordinate.latitude)
    }

    @Test("All tiles share fixed Zoom 12 coarseness without hierarchy")
    func testFixedZoomTiles() {
        #expect(MapTileGrid.zoom == 12)
    }
}
