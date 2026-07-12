import XCTest
@testable import Framelet

@MainActor
final class TimelineInteractionTests: XCTestCase {
    func testMovingSegmentPreservesDuration() {
        let result = TimelineNSView.movedRange(start: 10, end: 25, delta: 12, duration: 100)

        XCTAssertEqual(result.start, 22, accuracy: 0.000_001)
        XCTAssertEqual(result.end, 37, accuracy: 0.000_001)
    }

    func testMovingSegmentClampsAtTimelineStart() {
        let result = TimelineNSView.movedRange(start: 10, end: 25, delta: -30, duration: 100)

        XCTAssertEqual(result.start, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.end, 15, accuracy: 0.000_001)
    }

    func testMovingSegmentClampsAtTimelineEnd() {
        let result = TimelineNSView.movedRange(start: 80, end: 95, delta: 30, duration: 100)

        XCTAssertEqual(result.start, 85, accuracy: 0.000_001)
        XCTAssertEqual(result.end, 100, accuracy: 0.000_001)
    }
}
