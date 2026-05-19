import XCTest
@testable import HAL9000

final class CoachFeatureTests: XCTestCase {
    func testMarkdownParserExtractsTableAndListBlocks() {
        let blocks = CoachMarkdownRenderer.parse(
            """
            **建议：减量。**

            | 选项 | 安排 |
            |---|---|
            | A | 休息 |
            | B | 轻松跑 |

            - 看 HRV
            - 看腿感
            """
        )

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].kind, .paragraph("**建议：减量。**"))
        XCTAssertEqual(blocks[1].kind, .table([["选项", "安排"], ["A", "休息"], ["B", "轻松跑"]]))
        XCTAssertEqual(blocks[2].kind, .list(["看 HRV", "看腿感"]))
    }

    func testPlanPatchBuildsTrainingSessions() {
        let patch = CoachPlanPatch(
            weekStart: "2026-05-25",
            sessions: [
                CoachPlanSession(
                    day: "周一",
                    type: "轻松跑",
                    distanceKm: 8,
                    zone: "Z1-Z2",
                    detail: "恢复跑，心率控制"
                )
            ]
        )

        let sessions = CoachPlanSyncService().sessions(from: patch)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].name, "周一 轻松跑")
        XCTAssertEqual(sessions[0].distance, 8000)
        XCTAssertEqual(sessions[0].plannedDistance, 8000)
        XCTAssertEqual(sessions[0].zone, "Z1-Z2")
        XCTAssertEqual(sessions[0].description, "恢复跑，心率控制")
    }
}
