import CoreLocation
import SwiftUI
import Testing
@testable import KomunikacjaWiejska

/// Presentation, formatting, zoom calculation, and marker rotation tests.

@Suite("Presentation & UI Mapping Tests")
struct PresentationTests {
    @Test("RouteType presentation properties are distinct and localized")
    func testRouteTypePresentation() {
        #expect(RouteType.tram.systemImageName == "tram.fill")
        #expect(RouteType.subway.systemImageName == "tram.fill.tunnel")
        #expect(RouteType.rail.systemImageName == "train.side.front.car")
        #expect(RouteType.bus.systemImageName == "bus.fill")
        #expect(RouteType.ferry.systemImageName == "ferry.fill")
        #expect(RouteType.trolleybus.systemImageName == "bus.doubledecker.fill")
        #expect(RouteType.aerialLift.systemImageName == "cablecar.fill")
        #expect(RouteType.funicular.systemImageName == "cablecar")
        #expect(RouteType.monorail.systemImageName == "train.side.middle.car")
        #expect(RouteType.unknown.systemImageName == "questionmark.circle.fill")

        for type in RouteType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(!type.defaultHexColor.isEmpty)
            #expect(!type.systemImageName.isEmpty)
        }

        #expect(RouteType.unknown.systemImageName != RouteType.bus.systemImageName)
        #expect(RouteType.unknown.systemImageName != RouteType.tram.systemImageName)
        #expect(RouteType.unknown.defaultHexColor != RouteType.bus.defaultHexColor)
    }

    @Test("Hex Color parsing supports 3, 6, 8 digit forms with/without # and rejects malformed inputs")
    func testColorHexParsing() throws {
        let white = try #require(Color(hex: "#fff"))
        let whiteComponents = rgba(white)
        #expect(whiteComponents.red == 1 && whiteComponents.green == 1 && whiteComponents.blue == 1)

        let rawHex = Color(hex: "415f91")
        #expect(rawHex != nil)

        let red = try #require(Color(hex: "#ff0000"))
        #expect(rgba(red).red == 1)

        let translucentRed = try #require(Color(hex: "#80ff0000"))
        let trComponents = rgba(translucentRed)
        #expect(trComponents.red == 1)
        #expect(abs(trComponents.alpha - (128.0 / 255.0)) < 0.02)

        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#12") == nil)
        #expect(Color(hex: "#abcd") == nil)
        #expect(Color(hex: "#abcde") == nil)
        #expect(Color(hex: "#abcdef0") == nil)
        #expect(Color(hex: "#gggggg") == nil)

        #expect(rgba(Color(hex: "nope", fallback: .blue)).blue == 1)
    }

    @Test("Contrasting text color selects black on light fills and white on dark fills")
    func testContrastingTextColor() {
        #expect(Color.contrastingTextColor(forHex: "#FFFFFF") == .black)
        #expect(Color.contrastingTextColor(forHex: "#FFFF00") == .black)
        #expect(Color.contrastingTextColor(forHex: "FFF") == .black)
        #expect(Color.contrastingTextColor(forHex: "#A8F0C6") == .black)

        #expect(Color.contrastingTextColor(forHex: "#000000") == .white)
        #expect(Color.contrastingTextColor(forHex: "#0000FF") == .white)
        #expect(Color.contrastingTextColor(forHex: "#1E3A8A") == .white)
        #expect(Color.contrastingTextColor(forHex: "#D97706") == .white)
        #expect(Color.contrastingTextColor(forHex: "000") == .white)

        #expect(Color.contrastingTextColor(forHex: "invalid", fallback: .white) == .white)
        #expect(Color.contrastingTextColor(forHex: "", fallback: .black) == .black)
    }

    private func rgba(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    @Test("MapMode identifiers stay stable while display names are localized")
    @MainActor
    func testMapModes() {
        #expect(MapMode.allCases.count == 2)
        #expect(MapMode.explore.rawValue == "Explore")
        #expect(MapMode.satellite.rawValue == "Satellite")
        #expect(MapMode.explore.id == "Explore")
        #expect(MapMode.satellite.id == "Satellite")
        #expect(!MapMode.explore.displayName.isEmpty)
        #expect(MapMode.explore.displayName != MapMode.satellite.displayName)
    }

    @Test("BoundingBox calculates Web Mercator zoom across overview and neighborhood spans")
    func testWebMercatorZoomDerivation() {
        let zoomedOut = BoundingBox(minLon: 19.7, minLat: 49.9, maxLon: 20.2, maxLat: 50.2)
        let streetLevel = BoundingBox(minLon: 19.93, minLat: 50.06, maxLon: 19.94, maxLat: 50.07)

        #expect(zoomedOut.webMercatorZoom() < streetLevel.webMercatorZoom())
        #expect(streetLevel.webMercatorZoom() >= 15.0)
        #expect(zoomedOut.webMercatorZoom() <= 14.5)
    }

    @Test("StopMarkerView effectiveRotation offsets camera heading smoothly")
    @MainActor
    func testStopMarkerViewEffectiveRotation() {
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 0) == 90)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 0) == 0)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 0) == 180)
        #expect(StopMarkerView.effectiveRotation(bearing: 270, heading: 0) == 270)
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 90) == 0)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 90) == -90)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 90) == 90)
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 180) == -90)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 45) == -45)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 350) == -170)
    }

    @Test("StopDetailSheet instantiates cleanly with static metadata and live departures")
    @MainActor
    func testStopDetailSheetRenders() {
        let stop = StubStopsProvider.sampleStop(
            routes: RouteType.displayableCases.enumerated().map { idx, type in
                StubStopsProvider.sampleRoute(id: "\(idx)", name: "\(idx + 1)", type: type)
            }
        )
        let departure = StopDeparture(
            trip: TripInfo(
                id: "trip-1",
                city: "warsaw",
                route: StubStopsProvider.sampleRoute(),
                headsign: "Marysin",
                brigade: "1"
            ),
            vehicle: StubStopsProvider.sampleVehicle(),
            departure: StopTimeUpdate(scheduledMs: 1_794_433_020_000, delayMs: 120_000, status: .onTrip, platform: "2")
        )
        let sheet = StopDetailSheet(stop: stop, departures: [departure], onDismiss: {})
        _ = sheet.body
    }

    @Test("VehicleDetailSheet renders full itinerary, alerts, metadata, and DotMarkerView without crashing")
    @MainActor
    func testVehicleDetailSheetRenders() {
        let stop = StubStopsProvider.sampleStop(id: "s1", name: "Hala Wola")
        let detail = ActiveTripDetail(
            city: "krakow",
            vehicleId: "3:DE631",
            tripId: "trip-124",
            route: StubStopsProvider.sampleRoute(name: "124"),
            headsign: "Tauron Arena",
            brigade: "124-01",
            tripInfo: TripInfo(
                id: "trip-124",
                city: "krakow",
                route: StubStopsProvider.sampleRoute(name: "124"),
                headsign: "Tauron Arena",
                brigade: "124-01",
                descriptionPairs: [["Info", "Kurs niskoemisyjny"]]
            ),
            itinerary: Itinerary(
                stops: [
                    ItineraryStop(stop: stop, alight: .regular, platform: "1"),
                    ItineraryStop(stop: StubStopsProvider.sampleStop(id: "s2", name: "Rondo"), alight: .onDemand)
                ],
                encodedPolyline: "o_pp~Ai}v_e@?g@"
            ),
            livePosition: StubStopsProvider.sampleVehicle(percentTraveled: 50),
            stopUpdates: [
                TripStopUpdate(
                    arrival: StopTimeUpdate(scheduledMs: 1_794_432_060_000, delayMs: 0, status: .onTrip),
                    departure: StopTimeUpdate(scheduledMs: 1_794_432_060_000, delayMs: 0, status: .onTrip)
                ),
                TripStopUpdate(
                    arrival: StopTimeUpdate(scheduledMs: 1_794_432_240_000, delayMs: 120_000, status: .onTrip),
                    departure: StopTimeUpdate(scheduledMs: 1_794_432_240_000, delayMs: 120_000, status: .onTrip),
                    track: "3"
                )
            ],
            currentSequence: 1,
            alerts: [TripAlert(title: "Objazd", description: "Trasa zmieniona")],
            vehicleMetadata: VehicleMetadata(id: "3:DE631", model: "Solaris Urbino 12", prodYear: 2023, carrier: "MPK Kraków"),
            isLoading: false
        )
        let sheet = VehicleDetailSheet(
            detail: detail,
            canNavigateBack: true,
            isFollowingVehicle: true,
            onDismiss: {}
        )
        _ = sheet.body

        let dotView = DotMarkerView(dot: StubStopsProvider.sampleDot())
        _ = dotView.body
    }

    @Test("VehicleDetailSheet delay status uses >= 1 minute threshold without sub-minute gaps")
    @MainActor
    func testVehicleDelayStatusFormatting() {
        #expect(VehicleDetailSheet.delayStatus(for: 0) == .onTime)
        #expect(VehicleDetailSheet.delayStatus(for: 30_000) == .onTime)
        #expect(VehicleDetailSheet.delayStatus(for: 59_999) == .onTime)
        #expect(VehicleDetailSheet.delayStatus(for: -59_999) == .onTime)

        #expect(VehicleDetailSheet.delayStatus(for: 60_000) == .delayed(minutes: 1))
        #expect(VehicleDetailSheet.delayStatus(for: 179_999) == .delayed(minutes: 2))
        #expect(VehicleDetailSheet.delayStatus(for: -60_000) == .early(minutes: 1))
        #expect(VehicleDetailSheet.delayStatus(for: -180_000) == .early(minutes: 3))

        #expect(VehicleDetailSheet.delayStatus(for: 120_000).color == .red)
        #expect(VehicleDetailSheet.delayStatus(for: -120_000).color == .orange)
        #expect(VehicleDetailSheet.delayStatus(for: 0).color == .green)
    }

    @Test("TransitTimeFormatting covers Scheduled, Cancelled, Delayed, Early, and countdown/clock strings")
    @MainActor
    func testTransitTimeFormattingAndCountdown() throws {
        let nowMs: Int64 = 1_762_975_800_000
        let now = Date(timeIntervalSince1970: Double(nowMs) / 1_000.0)

        #expect(VehicleDetailSheet.countdownText(estimatedMs: nowMs - 15_000, now: now) == "<1")
        #expect(VehicleDetailSheet.countdownText(estimatedMs: nowMs, now: now) == "<1")
        #expect(VehicleDetailSheet.countdownText(estimatedMs: nowMs + 29_000, now: now) == "<1")
        #expect(VehicleDetailSheet.countdownText(estimatedMs: nowMs + 30_000, now: now) == "1")
        #expect(VehicleDetailSheet.countdownText(estimatedMs: nowMs + 31_000, now: now) == "1")
        #expect(VehicleDetailSheet.countdownText(estimatedMs: nowMs + 89_000, now: now) == "1")
        #expect(VehicleDetailSheet.countdownText(estimatedMs: nowMs + 91_000, now: now) == "2")

        let warsaw = try #require(TimeZone(identifier: "Europe/Warsaw"))
        let components = DateComponents(year: 2026, month: 11, day: 12, hour: 20, minute: 31)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = warsaw
        let epochMs = Int64(try #require(calendar.date(from: components)).timeIntervalSince1970 * 1_000.0)
        #expect(VehicleDetailSheet.formattedTime(epochMs: epochMs, timeZone: warsaw) == "20:31")

        #expect(TransitTimeFormatting.presentation(for: StopTimeUpdate(scheduledMs: nowMs, delayMs: 120_000, status: .scheduled)) == .scheduled)
        #expect(TransitTimeFormatting.presentation(for: StopTimeUpdate(scheduledMs: nowMs, delayMs: 0, status: .cancelled)) == .cancelled)
        #expect(TransitTimeFormatting.presentation(for: StopTimeUpdate(scheduledMs: nowMs, delayMs: 120_000, status: .onTrip)) == .delayed(minutes: 2))
        #expect(TransitTimeFormatting.presentation(for: StopTimeUpdate(scheduledMs: nowMs, delayMs: -60_000, status: .onPreviousTrip)) == .early(minutes: 1))
    }

    @Test("VehicleMarkerView effectiveRotation offsets heading")
    @MainActor
    func testVehicleMarkerViewEffectiveRotation() {
        #expect(VehicleMarkerView.effectiveRotation(bearing: 180, heading: 0) == 180)
        #expect(VehicleMarkerView.effectiveRotation(bearing: 180, heading: 90) == 90)
        #expect(VehicleMarkerView.effectiveRotation(bearing: 90, heading: 90) == 0)
    }
}
