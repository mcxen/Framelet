import Foundation
import XCTest
@testable import Framelet

final class ProcessRunnerTests: XCTestCase {
    func testLosslessExportSeeksAfterInputAndPreservesStreamCopy() {
        let segment = Segment(name: "Cut", sourceStart: 124.934, sourceEnd: 467.077)
        let job = makeExportJob(segment: segment)

        let arguments = FFmpegExportCommandBuilder.segmentArguments(
            segment: segment,
            sourceStart: segment.sourceStart,
            outputURL: URL(fileURLWithPath: "/tmp/output.mov"),
            job: job
        )

        XCTAssertLessThan(
            try XCTUnwrap(arguments.firstIndex(of: "-i")),
            try XCTUnwrap(arguments.firstIndex(of: "-ss"))
        )
        XCTAssertTrue(arguments.containsSequence(["-c", "copy"]))
        XCTAssertFalse(arguments.contains("h264_videotoolbox"))
        XCTAssertFalse(arguments.contains("-map_metadata:s"))
    }

    func testCropExportReencodesOnlyVideo() {
        let segment = Segment(name: "Crop", sourceStart: 1, sourceEnd: 3)
        var job = makeExportJob(segment: segment)
        job.cropRectangle = CropRectangle(x: 2, y: 4, width: 640, height: 480)

        let arguments = FFmpegExportCommandBuilder.codecArguments(for: job)

        XCTAssertTrue(arguments.containsSequence(["-vf", "crop=640:480:2:4"]))
        XCTAssertTrue(arguments.containsSequence(["-c:v", "h264_videotoolbox"]))
        XCTAssertTrue(arguments.containsSequence(["-c:a", "copy"]))
        XCTAssertFalse(arguments.containsSequence(["-c", "copy"]))
    }

    func testMergedSegmentForcesDecodableVideoStartWithoutApplyingCrop() {
        let segment = Segment(name: "Merged", sourceStart: 10, sourceEnd: 10.5)
        let job = makeExportJob(segment: segment)

        let arguments = FFmpegExportCommandBuilder.segmentArguments(
            segment: segment,
            sourceStart: segment.sourceStart,
            outputURL: URL(fileURLWithPath: "/tmp/merged-part.mov"),
            job: job,
            forceVideoEncode: true
        )

        XCTAssertTrue(arguments.containsSequence(["-c:v", "h264_videotoolbox"]))
        XCTAssertTrue(arguments.containsSequence(["-c:a", "aac"]))
        XCTAssertLessThan(
            try XCTUnwrap(arguments.firstIndex(of: "-ss")),
            try XCTUnwrap(arguments.firstIndex(of: "-i"))
        )
        XCTAssertFalse(arguments.contains("-vf"))
    }

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

    private func makeExportJob(segment: Segment) -> ExportJob {
        ExportJob(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            segments: [segment],
            selectedStreamIndexes: [0, 1],
            mode: .separateFiles,
            containerExtension: "mov",
            namingPattern: "{name}",
            baseName: "Test",
            sourceBaseName: "input",
            cropRectangle: nil,
            videoEncode: VideoEncodeSettings(),
            metadataOverrides: [:]
        )
    }
}

private extension Array where Element: Equatable {
    func containsSequence(_ sequence: [Element]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= count else { return false }
        return indices.dropLast(sequence.count - 1).contains { index in
            Array(self[index..<(index + sequence.count)]) == sequence
        }
    }
}
