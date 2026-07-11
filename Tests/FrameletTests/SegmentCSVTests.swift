import XCTest
@testable import Framelet

final class SegmentCSVTests: XCTestCase {
    func testRejectsNonFinitePlainTimes() {
        for value in ["nan", "inf", "-inf", "infinity"] {
            XCTAssertThrowsError(try SegmentCSV.decode("Start,End,Name\n0,\(value),Bad\n", duration: nil))
            XCTAssertThrowsError(try SegmentCSV.decode("Start,End,Name\n\(value),2,Bad\n", duration: 10))
        }
    }

    func testRejectsNonFiniteTimecodeComponents() {
        for value in ["00:inf", "nan:01", "inf:00:01"] {
            XCTAssertThrowsError(try SegmentCSV.decode("Start,End,Name\n0,\(value),Bad\n", duration: nil))
        }
    }
}
