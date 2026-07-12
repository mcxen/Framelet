import Foundation
import XCTest
@testable import Framelet

final class ProcessRunnerTests: XCTestCase {
    func testFFmpegProgressParserHandlesSplitOutput() {
        let parser = FFmpegProgressParser()

        XCTAssertTrue(parser.consume(Data("out_time_".utf8)).isEmpty)
        XCTAssertEqual(
            parser.consume(Data("us=1250000\nspeed=1.2x\nout_time_us=2500000\n".utf8)),
            [
                FFmpegProgressUpdate(elapsed: 1.25, speed: nil),
                FFmpegProgressUpdate(elapsed: 2.5, speed: 1.2)
            ]
        )
    }

    func testFFmpegProgressParserAcceptsBothTimestampKeys() {
        let parser = FFmpegProgressParser()

        XCTAssertEqual(
            parser.consume(Data("speed=2.5x\nout_time_ms=3000000\n".utf8)),
            [FFmpegProgressUpdate(elapsed: 3, speed: 2.5)]
        )
    }

    func testDrainsLargeStdoutAndStderrWithoutDeadlock() async throws {
        let byteCount = 2_000_000
        let output = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [
                "-c",
                "import sys; sys.stdout.write('o' * \(byteCount)); sys.stderr.write('e' * \(byteCount))"
            ]
        )

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout.count, byteCount)
        XCTAssertEqual(output.stderr.count, byteCount)
    }

    func testReportsNonzeroExitAndStderrTail() async {
        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo expected-error >&2; exit 7"]
            )
            XCTFail("Expected process failure")
        } catch let error as MediaError {
            guard case let .processFailed(executable, exitCode, summary) = error else {
                return XCTFail("Unexpected media error: \(error)")
            }
            XCTAssertEqual(executable, "sh")
            XCTAssertEqual(exitCode, 7)
            XCTAssertTrue(summary.contains("expected-error"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
