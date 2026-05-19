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
}
