import AppKit
import XCTest
@testable import Framelet

final class ExportPresetTests: XCTestCase {
    func testDefaultNamingPatternUsesSourceAndTimestamp() {
        XCTAssertEqual(
            ExportPreset().namingPattern,
            "{source}-{timestamp}-{index}"
        )
    }

    func testNewProjectStartsWithoutSegments() {
        XCTAssertTrue(EditingProject.empty().segments.isEmpty)
    }

    @MainActor
    func testCreatingSegmentRequiresValidInAndOutPoints() {
        let store = EditorStore(services: AppServices())
        store.duration = 60
        store.currentTime = 10

        store.createSegmentFromMarks()
        XCTAssertTrue(store.project.segments.isEmpty)
        XCTAssertFalse(store.canCreateSegmentFromMarks)

        store.inPoint = 10
        store.outPoint = 15
        XCTAssertTrue(store.canCreateSegmentFromMarks)

        store.createSegmentFromMarks()
        XCTAssertEqual(store.project.segments.count, 1)
        XCTAssertEqual(store.project.segments.first?.sourceStart, 10)
        XCTAssertEqual(store.project.segments.first?.sourceEnd, 15)
    }

    @MainActor
    func testTinyTimelineSegmentDoesNotCreateNegativeCursorRect() {
        let timeline = TimelineNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 260))
        timeline.duration = 7_200
        timeline.visibleDuration = 7_200
        timeline.segments = [
            Segment(name: "Tiny", sourceStart: 10, sourceEnd: 10.05)
        ]

        timeline.resetCursorRects()
    }
}
