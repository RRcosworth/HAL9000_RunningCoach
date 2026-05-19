import XCTest
@testable import HAL9000

final class TSBCalculatorTests: XCTestCase {
    func testCalculateUsesPreviousDayForTSB() {
        let start = Date(timeIntervalSince1970: 0)
        let days = [
            (date: start, tss: 100.0),
            (date: start.addingTimeInterval(86_400), tss: 0.0)
        ]

        let result = TSBCalculator().calculate(dailyTSS: days)

        XCTAssertEqual(result.history.count, 2)
        XCTAssertEqual(result.history[0].ctl, 100.0, accuracy: 0.001)
        XCTAssertEqual(result.history[0].atl, 100.0, accuracy: 0.001)
        XCTAssertEqual(result.history[0].tsb, 0.0, accuracy: 0.001)
        XCTAssertEqual(result.history[1].ctl, 97.619, accuracy: 0.001)
        XCTAssertEqual(result.history[1].atl, 85.714, accuracy: 0.001)
        XCTAssertEqual(result.history[1].tsb, 0.0, accuracy: 0.001)
    }

    func testStateThresholds() {
        let calculator = TSBCalculator()

        XCTAssertEqual(calculator.state(for: 11, hasEnoughData: true), .fresh)
        XCTAssertEqual(calculator.state(for: 0, hasEnoughData: true), .neutral)
        XCTAssertEqual(calculator.state(for: -20, hasEnoughData: true), .fatigued)
        XCTAssertEqual(calculator.state(for: -31, hasEnoughData: true), .highRisk)
        XCTAssertEqual(calculator.state(for: 20, hasEnoughData: false), .noData)
    }

    func testHighRecentLoadCreatesNegativeTSBTrend() {
        let start = Date(timeIntervalSince1970: 0)
        let days = (0..<10).map { offset in
            (
                date: start.addingTimeInterval(Double(offset) * 86_400),
                tss: offset < 5 ? 40.0 : 140.0
            )
        }

        let result = TSBCalculator().calculate(dailyTSS: days)

        XCTAssertLessThan(result.current.tsb, 0)
        XCTAssertGreaterThan(result.current.atl, result.current.ctl)
    }
}
