import XCTest
@testable import HAL9000

final class RaceLogClassificationTests: XCTestCase {
    func testRaceCategoryUsesOnlyTenKHalfAndMarathonPBClasses() {
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 5_000), .other)
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 9_500), .tenK)
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 10_800), .tenK)
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 20_050), .half)
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 22_790), .half)
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 40_090), .full)
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 45_580), .full)
        XCTAssertEqual(RaceCategory.classify(distanceMeters: 46_000), .other)
    }

    func testPBCategoriesExcludeOther() {
        XCTAssertEqual(RaceCategory.pbCategories, [.tenK, .half, .full])
        XCTAssertFalse(RaceCategory.pbCategories.contains(.other))
    }
}
