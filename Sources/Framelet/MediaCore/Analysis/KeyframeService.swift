import Foundation

protocol KeyframeService: Sendable {
    func loadKeyframes(from url: URL, streamIndex: Int, startTime: Double) async throws -> KeyframeIndex
}

struct FFprobeKeyframeService: KeyframeService {
    private let executableResolver: ToolResolver
    private let commandLog: CommandLog?

    init(executableResolver: ToolResolver = ToolResolver(), commandLog: CommandLog? = nil) {
        self.executableResolver = executableResolver
        self.commandLog = commandLog
    }

    func loadKeyframes(from url: URL, streamIndex: Int, startTime: Double) async throws -> KeyframeIndex {
        guard let executable = executableResolver.resolve("ffprobe") else {
            throw MediaError.ffprobeNotFound
        }

        let output = try await ProcessRunner.run(
            executableURL: executable,
            arguments: [
                "-v", "error",
                "-select_streams", "v:\(streamIndex)",
                "-skip_frame", "nokey",
                "-show_frames",
                "-show_entries", "frame=best_effort_timestamp_time,pkt_pts_time,pts_time,pkt_duration_time",
                "-of", "json",
                url.path
            ],
            commandLog: commandLog
        )

        let response = try JSONDecoder().decode(FFprobeFramesResponse.self, from: output.stdout)
        let safeStartTime = max(0, startTime)
        return KeyframeIndex(response.frames.compactMap { frame in
            frame.timestamp.map { $0 - safeStartTime }
        })
    }
}

private struct FFprobeFramesResponse: Decodable {
    var frames: [FFprobeFrame] = []
}

private struct FFprobeFrame: Decodable {
    var bestEffortTimestampTime: LossyFrameNumber?
    var packetPresentationTimestampTime: LossyFrameNumber?
    var presentationTimestampTime: LossyFrameNumber?
    var packetDurationTime: LossyFrameNumber?

    enum CodingKeys: String, CodingKey {
        case bestEffortTimestampTime = "best_effort_timestamp_time"
        case packetPresentationTimestampTime = "pkt_pts_time"
        case presentationTimestampTime = "pts_time"
        case packetDurationTime = "pkt_duration_time"
    }

    var timestamp: Double? {
        bestEffortTimestampTime?.value ?? packetPresentationTimestampTime?.value ?? presentationTimestampTime?.value
    }
}

private struct LossyFrameNumber: Decodable {
    var value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self), let double = Double(string) {
            value = double
        } else {
            value = 0
        }
    }
}
