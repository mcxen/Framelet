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
}
