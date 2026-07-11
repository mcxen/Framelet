import Foundation

struct FFprobeService: MediaProbeService {
    private let executableResolver: ToolResolver
    private let commandLog: CommandLog?

    init(executableResolver: ToolResolver = ToolResolver(), commandLog: CommandLog? = nil) {
        self.executableResolver = executableResolver
        self.commandLog = commandLog
    }

    func probe(_ url: URL) async throws -> MediaInfo {
        guard let executable = executableResolver.resolve("ffprobe") else {
            throw MediaError.ffprobeNotFound
        }

        let data = try await ProcessRunner.run(
            executableURL: executable,
            arguments: [
                "-v", "error",
                "-show_format",
                "-show_streams",
                "-show_chapters",
                "-of", "json",
                url.path
            ],
            commandLog: commandLog
        )

        let response = try JSONDecoder().decode(FFprobeResponse.self, from: data.stdout)
        return response.mediaInfo(url: url)
    }
}

private struct FFprobeResponse: Decodable {
    var streams: [FFprobeStream]?
    var chapters: [FFprobeChapter]?
    var format: FFprobeFormat?

    func mediaInfo(url: URL) -> MediaInfo {
        MediaInfo(
            url: url,
            formatName: format?.formatName,
            duration: format?.duration?.doubleValue,
            size: format?.size?.int64Value,
            bitRate: format?.bitRate?.int64Value,
            streams: (streams ?? []).map(\.mediaStream),
            chapters: (chapters ?? []).map(\.mediaChapter)
        )
    }
}

private struct FFprobeFormat: Decodable {
    var formatName: String?
    var duration: LossyNumber?
    var size: LossyNumber?
    var bitRate: LossyNumber?

    enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case duration
        case size
        case bitRate = "bit_rate"
    }
}

private struct FFprobeStream: Decodable {
    var index: Int
    var codecType: String?
    var codecName: String?
    var codecLongName: String?
    var profile: String?
    var width: Int?
    var height: Int?
    var rFrameRate: String?
    var avgFrameRate: String?
    var timeBase: String?
    var sampleRate: LossyNumber?
    var channels: Int?
    var channelLayout: String?
    var tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case index
        case codecType = "codec_type"
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case profile
        case width
        case height
        case rFrameRate = "r_frame_rate"
        case avgFrameRate = "avg_frame_rate"
        case timeBase = "time_base"
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
        case tags
    }

    var mediaStream: MediaStream {
        MediaStream(
            index: index,
            kind: MediaStreamKind(rawValue: codecType ?? "") ?? .unknown,
            codecName: codecName,
            codecLongName: codecLongName,
            profile: profile,
            width: width,
            height: height,
            frameRate: Self.parseFrameRate(avgFrameRate) ?? Self.parseFrameRate(rFrameRate),
            timeBase: timeBase,
            sampleRate: sampleRate?.intValue,
            channels: channels,
            channelLayout: channelLayout,
            language: tags?["language"]
        )
    }

    private static func parseFrameRate(_ value: String?) -> Double? {
        guard let value, value != "0/0" else { return nil }
        let parts = value.split(separator: "/").compactMap { Double($0) }
        if parts.count == 2, parts[1] != 0 {
            return parts[0] / parts[1]
        }
        return Double(value)
    }
}

private struct FFprobeChapter: Decodable {
    var id: Int?
    var startTime: LossyNumber?
    var endTime: LossyNumber?
    var tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case tags
    }

    var mediaChapter: MediaChapter {
        MediaChapter(
            index: id ?? 0,
            start: startTime?.doubleValue ?? 0,
            end: endTime?.doubleValue ?? 0,
            title: tags?["title"]
        )
    }
}

private struct LossyNumber: Decodable {
    var doubleValue: Double
    var intValue: Int { Int(doubleValue) }
    var int64Value: Int64 { Int64(doubleValue) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            doubleValue = double
        } else if let string = try? container.decode(String.self), let double = Double(string) {
            doubleValue = double
        } else {
            doubleValue = 0
        }
    }
}
