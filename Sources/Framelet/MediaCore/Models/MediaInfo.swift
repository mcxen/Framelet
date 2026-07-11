import Foundation

struct MediaInfo: Codable, Hashable, Sendable {
    var url: URL
    var formatName: String?
    var startTime: Double?
    var duration: Double?
    var size: Int64?
    var bitRate: Int64?
    var streams: [MediaStream]
    var chapters: [MediaChapter]
    var metadata: [String: String]

    var videoStreams: [MediaStream] { streams.filter { $0.kind == .video } }
    var audioStreams: [MediaStream] { streams.filter { $0.kind == .audio } }
    var subtitleStreams: [MediaStream] { streams.filter { $0.kind == .subtitle } }

    var timelineStartTime: Double {
        let candidates = [
            videoStreams.first?.startTime,
            streams.first?.startTime,
            startTime
        ]
        return max(0, candidates.compactMap { $0 }.first ?? 0)
    }

    var displayDuration: Double? {
        duration.map { max(0, $0) }
    }

    /// QuickTime commonly stores camera/EXIF-style values on either the container or
    /// the video stream. Merge both so creation date, device and location are visible.
    var allMetadata: [String: String] {
        var result: [String: String] = [:]
        for stream in streams { result.merge(stream.metadata) { current, _ in current } }
        result.merge(metadata) { _, container in container }
        return result
    }

    func metadataValue(for keys: [String]) -> String? {
        let normalized = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.key.lowercased(), $0.value) })
        return keys.lazy.compactMap { normalized[$0.lowercased()] }.first
    }

    var creationDateText: String? {
        metadataValue(for: ["creation_time", "date", "com.apple.quicktime.creationdate"])
    }

    var cameraText: String? {
        let make = metadataValue(for: ["com.apple.quicktime.make", "make"])
        let model = metadataValue(for: ["com.apple.quicktime.model", "model"])
        return [make, model].compactMap { $0 }.joined(separator: " ").nilIfEmpty
    }

    var locationText: String? {
        metadataValue(for: ["com.apple.quicktime.location.ISO6709", "location", "location-eng"])
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct MediaStream: Identifiable, Codable, Hashable, Sendable {
    var id: Int { index }
    var index: Int
    var kind: MediaStreamKind
    var codecName: String?
    var codecLongName: String?
    var profile: String?
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var startTime: Double?
    var timeBase: String?
    var sampleRate: Int?
    var channels: Int?
    var channelLayout: String?
    var language: String?
    var metadata: [String: String]

    var displayName: String {
        let codec = codecName ?? "unknown"
        switch kind {
        case .video:
            if let width, let height {
                return "#\(index) Video \(codec) \(width)x\(height)"
            }
            return "#\(index) Video \(codec)"
        case .audio:
            let channelText = channels.map { "\($0) ch" } ?? "audio"
            return "#\(index) Audio \(codec) \(channelText)"
        case .subtitle:
            return "#\(index) Subtitle \(codec)"
        case .data:
            return "#\(index) Data \(codec)"
        case .attachment:
            return "#\(index) Attachment \(codec)"
        case .unknown:
            return "#\(index) Stream \(codec)"
        }
    }
}

enum MediaStreamKind: String, Codable, Hashable, Sendable {
    case video
    case audio
    case subtitle
    case data
    case attachment
    case unknown
}

struct MediaChapter: Identifiable, Codable, Hashable, Sendable {
    var id: Int { index }
    var index: Int
    var start: Double
    var end: Double
    var title: String?
}
