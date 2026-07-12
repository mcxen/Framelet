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
    func testSegmentPreviewProgressIsRelativeAndClamped() {
        let store = EditorStore(services: AppServices())
        let segment = Segment(name: "Preview", sourceStart: 10, sourceEnd: 30)

        store.currentTime = 15
        XCTAssertEqual(store.segmentPreviewProgress(for: segment), 0.25, accuracy: 0.000_001)

        store.currentTime = 5
        XCTAssertEqual(store.segmentPreviewProgress(for: segment), 0, accuracy: 0.000_001)

        store.currentTime = 35
        XCTAssertEqual(store.segmentPreviewProgress(for: segment), 1, accuracy: 0.000_001)
    }

    @MainActor
    func testSeekingSegmentPreviewUsesSegmentRelativeProgress() {
        let segment = Segment(name: "Preview", sourceStart: 10, sourceEnd: 30)
        var project = EditingProject.empty(name: "Preview")
        project.segments = [segment]
        let store = EditorStore(project: project, services: AppServices())
        store.duration = 60
        store.selectedSegmentID = segment.id

        store.seekSelectedSegmentPreview(to: 0.25)
        XCTAssertEqual(store.currentTime, 15, accuracy: 0.000_001)
        XCTAssertEqual(store.previewingSegmentID, segment.id)

        store.seekSelectedSegmentPreview(to: 2)
        XCTAssertEqual(store.currentTime, 30, accuracy: 0.000_001)
    }

    @MainActor
    func testSegmentPreviewCanResumeAfterPausing() {
        let segment = Segment(name: "Preview", sourceStart: 10, sourceEnd: 30)
        var project = EditingProject.empty(name: "Preview")
        project.segments = [segment]
        let store = EditorStore(project: project, services: AppServices())
        store.duration = 60
        store.selectedSegmentID = segment.id
        store.previewingSegmentID = segment.id
        store.currentTime = 18
        store.isPlaying = true

        store.toggleSelectedSegmentPreviewPlayback()
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.currentTime, 18, accuracy: 0.000_001)
        XCTAssertEqual(store.previewingSegmentID, segment.id)

        store.toggleSelectedSegmentPreviewPlayback()
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(store.currentTime, 18, accuracy: 0.000_001)
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
    func testCreatingMultipleSegmentsClearsMarksAndKeepsEachSegment() {
        let store = EditorStore(services: AppServices())
        store.duration = 90

        store.inPoint = 5
        store.outPoint = 12
        XCTAssertTrue(store.createSegment(start: 5, end: 12))
        XCTAssertNil(store.inPoint)
        XCTAssertNil(store.outPoint)
        XCTAssertFalse(store.canCreateSegmentFromMarks)

        store.inPoint = 30
        store.outPoint = 42
        XCTAssertTrue(store.createSegmentFromMarks())

        XCTAssertEqual(store.project.segments.map(\.name), ["Segment 1", "Segment 2"])
        XCTAssertEqual(store.project.segments.map(\.sourceStart), [5, 30])
        XCTAssertEqual(store.project.segments.map(\.sourceEnd), [12, 42])
        XCTAssertEqual(store.selectedSegment?.name, "Segment 2")
        XCTAssertNil(store.inPoint)
        XCTAssertNil(store.outPoint)
    }

    @MainActor
    func testSegmentsAllowOverlapButRejectFrameEquivalentDuplicates() {
        let store = EditorStore(services: AppServices())
        store.duration = 90

        XCTAssertTrue(store.createSegment(start: 10, end: 20))
        XCTAssertFalse(store.createSegment(start: 10.02, end: 20.02))
        XCTAssertEqual(store.project.segments.count, 1)
        XCTAssertTrue(store.createSegment(start: 15, end: 25))
        XCTAssertEqual(store.project.segments.count, 2)
    }

    @MainActor
    func testEditingSegmentCannotDuplicateAnotherAndNamesKeepIncreasing() {
        let store = EditorStore(services: AppServices())
        store.duration = 90
        XCTAssertTrue(store.createSegment(start: 10, end: 20))
        XCTAssertTrue(store.createSegment(start: 30, end: 40))
        let secondID = try! XCTUnwrap(store.project.segments.last?.id)

        store.updateSegment(id: secondID, start: 10, end: 20)
        XCTAssertEqual(store.project.segments.last?.sourceStart, 30)
        XCTAssertEqual(store.project.segments.last?.sourceEnd, 40)

        store.selectedSegmentID = store.project.segments.first?.id
        store.deleteSelectedSegment()
        XCTAssertTrue(store.createSegment(start: 50, end: 60))
        XCTAssertEqual(store.project.segments.last?.name, "Segment 3")
    }

    @MainActor
    func testSettingNewInPointStartsFreshMarkingState() {
        let store = EditorStore(services: AppServices())
        store.duration = 60
        store.createSegment(start: 20, end: 30)
        XCTAssertNotNil(store.selectedSegmentID)

        store.outPoint = 12
        store.currentTime = 10
        store.setInPoint()

        XCTAssertNil(store.selectedSegmentID)
        XCTAssertEqual(store.inPoint, 10)
        XCTAssertEqual(store.outPoint, 12)
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
