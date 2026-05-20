import XCTest
@testable import HAL9000

final class HeartRateZoneCalculatorTests: XCTestCase {
    func testClassifiesHeartRateZones() {
        let calculator = HeartRateZoneCalculator()
        let maxHR = 200.0

        XCTAssertEqual(calculator.classify(heartRate: 110, maxHR: maxHR), 1)
        XCTAssertEqual(calculator.classify(heartRate: 120, maxHR: maxHR), 2)
        XCTAssertEqual(calculator.classify(heartRate: 140, maxHR: maxHR), 3)
        XCTAssertEqual(calculator.classify(heartRate: 160, maxHR: maxHR), 4)
        XCTAssertEqual(calculator.classify(heartRate: 180, maxHR: maxHR), 5)
    }

    func testLoadTypeThresholds() {
        let calculator = HeartRateZoneCalculator()
        let maxHR = 200.0

        XCTAssertEqual(calculator.loadType(heartRate: 130, maxHR: maxHR), .lowAerobic)
        XCTAssertEqual(calculator.loadType(heartRate: 150, maxHR: maxHR), .highAerobic)
        XCTAssertEqual(calculator.loadType(heartRate: 180, maxHR: maxHR), .anaerobic)
    }

    func testZoneRange() {
        let calculator = HeartRateZoneCalculator()

        XCTAssertEqual(calculator.zoneRange(zone: 3, maxHR: 200), "140-160 bpm")
        XCTAssertEqual(calculator.zoneRange(zone: 9, maxHR: 200), "--")
    }

    func testZeroMaxHeartRateFallsBackSafely() {
        let calculator = HeartRateZoneCalculator()

        XCTAssertEqual(calculator.classify(heartRate: 150, maxHR: 0), 1)
        XCTAssertEqual(calculator.loadType(heartRate: 150, maxHR: 0), .lowAerobic)
        XCTAssertEqual(calculator.zoneRange(zone: 3, maxHR: 0), "0-0 bpm")
    }

    func testIntervalsStreamAcceptsWesternHemisphereAndPrimeMeridianCoordinates() throws {
        let newYork = IntervalsStream(type: "latlng", data: [40.7128, 40.7130, -74.0060, -74.0050])
        let london = IntervalsStream(type: "latlng", data: [51.5074, 51.5076, -0.1278, -0.1275])

        let newYorkCoordinate = try XCTUnwrap(newYork.startCoordinate)
        let londonCoordinate = try XCTUnwrap(london.startCoordinate)

        XCTAssertEqual(newYorkCoordinate.latitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(newYorkCoordinate.longitude, -74.0060, accuracy: 0.0001)
        XCTAssertEqual(londonCoordinate.latitude, 51.5074, accuracy: 0.0001)
        XCTAssertEqual(londonCoordinate.longitude, -0.1278, accuracy: 0.0001)
    }

    func testIntervalsStreamRejectsLatitudeOnlySequence() {
        let latitudeOnly = IntervalsStream(type: "latlng", data: [30.000, 30.010, 30.020, 30.030])

        XCTAssertNil(latitudeOnly.startCoordinate)
    }

    func testIntervalsStreamDecodesSeparateLatitudeLongitudeArrays() throws {
        let stream = IntervalsStream(
            type: "latlng",
            data: [30.1277, 30.1281],
            data2: [120.2613, 120.2620]
        )

        let start = try XCTUnwrap(stream.startCoordinate)

        XCTAssertEqual(stream.coordinates.count, 2)
        XCTAssertEqual(start.latitude, 30.1277, accuracy: 0.0001)
        XCTAssertEqual(start.longitude, 120.2613, accuracy: 0.0001)
    }

    func testIntervalsAltitudeGainIgnoresSmallGpsNoise() {
        let altitude = IntervalsStream(type: "altitude", data: [10.0, 10.5, 12.0, 11.8, 15.2, 14.9, 18.5])

        XCTAssertEqual(altitude.smoothedElevationGain ?? 0, 7.0, accuracy: 0.1)
    }

    func testIntervalsActivityDecodesLocalDateWithoutTimeZone() throws {
        let json = """
        [
          {
            "id": "race-1",
            "name": "Local Race",
            "type": "Run",
            "start_date_local": "2026-05-19T07:30:00",
            "distance": 10000,
            "moving_time": 2700
          }
        ]
        """.data(using: .utf8)!

        let activities = try JSONDecoder().decode([IntervalsActivity].self, from: json)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: activities[0].startDate)

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 30)
    }
}
