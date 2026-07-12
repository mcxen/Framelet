import XCTest
@testable import Framelet

@MainActor
final class UpdateServiceTests: XCTestCase {
    func testExtractsVersionFromRedirectedLatestReleaseURL() {
        XCTAssertEqual(
            UpdateService.releaseVersion(
                from: URL(string: "https://github.com/mcxen/Framelet/releases/tag/v1.2.3")
            ),
            "1.2.3"
        )
    }

    func testRejectsReleaseURLWithoutTag() {
        XCTAssertNil(
            UpdateService.releaseVersion(
                from: URL(string: "https://github.com/mcxen/Framelet/releases/latest")
            )
        )
    }
}
