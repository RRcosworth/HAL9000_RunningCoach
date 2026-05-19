import XCTest
@testable import HAL9000

final class TrainingLoadCalculatorTests: XCTestCase {
    func testDailyLoadUsesHeartRateFactorWhenAvailable() {
        let day = RunningLoadDay(
            date: Date(),
            runningDistanceKm: 10,
            exerciseMinutes: 60,
            averageHeartRate: 150,
            restingHeartRate: 50
        )

        let load = TrainingLoadCalculator().dailyLoad(day)

        XCTAssertEqual(load, 238.0, accuracy: 0.001)
    }

    func testCalculateRequiresEnoughDaysForLongTermLoad() {
        let days = makeDays(count: 13)

        let result = TrainingLoadCalculator().calculate(days: days)

        XCTAssertNotNil(result.shortTerm.value)
        XCTAssertNil(result.longTerm.value)
        XCTAssertEqual(result.balance, .unknown)
    }

    func testCalculateProducesLongTermLoadWithEnoughData() {
        let days = makeDays(count: 42)

        let result = TrainingLoadCalculator().calculate(days: days)

        XCTAssertNotNil(result.shortTerm.value)
        XCTAssertNotNil(result.longTerm.value)
    }

    private func makeDays(count: Int) -> [RunningLoadDay] {
        let start = Date(timeIntervalSince1970: 0)
        return (0..<count).map { offset in
            RunningLoadDay(
                date: start.addingTimeInterval(Double(offset) * 86_400),
                runningDistanceKm: 8,
                exerciseMinutes: 45,
                averageHeartRate: nil,
                restingHeartRate: nil
            )
        }
    }
}
