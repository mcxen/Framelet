import Foundation

struct MediaInfo: Codable, Hashable, Sendable {
    var url: URL
    var formatName: String?
    var duration: Double?
    var size: Int64?
    var bitRate: Int64?
    var streams: [MediaStream]
    var chapters: [MediaChapter]

    var videoStreams: [MediaStream] { streams.filter { $0.kind == .video } }
    var audioStreams: [MediaStream] { streams.filter { $0.kind == .audio } }
    var subtitleStreams: [MediaStream] { streams.filter { $0.kind == .subtitle } }
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
    var timeBase: String?
    var sampleRate: Int?
    var channels: Int?
    var channelLayout: String?
    var language: String?

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
