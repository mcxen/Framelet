import Foundation

struct ExportJob: Identifiable, Sendable {
    var id: UUID = UUID()
    var inputURL: URL
    var outputDirectory: URL
    var segments: [Segment]
    var selectedStreamIndexes: Set<Int>
    var mode: ExportMode
    var containerExtension: String
    var namingPattern: String
    var baseName: String
    var sourceBaseName: String
    var sourceStartOffset: Double = 0
    var exportTimestamp: Date = Date()
    var cropRectangle: CropRectangle?
    var videoEncode: VideoEncodeSettings
    var metadataOverrides: [String: String]
}

enum ExportEvent: Sendable {
    case preparing
    case processingSegment(current: Int, total: Int)
    case concatenating
    case progress(fraction: Double, speed: Double?)
    case completed(URL)
}

enum MediaError: LocalizedError, Sendable {
    case missingMedia
    case invalidSegmentRange
    case invalidCrop
    case invalidSegmentCSV(String)
    case ffprobeNotFound
    case ffmpegNotFound
    case processFailed(executable: String, exitCode: Int32, summary: String)
    case exportNotImplemented(String)
    case previewUnavailable

    var errorDescription: String? {
        switch self {
        case .missingMedia:
            "Open a media file before using this action."
        case .invalidSegmentRange:
            "The segment start time must be before the end time."
        case .invalidCrop:
            "The crop rectangle must have a valid width and height."
        case let .invalidSegmentCSV(message):
            message
        case .ffprobeNotFound:
            "FFprobe was not found. Install FFmpeg or place ffprobe in Resources/Tools."
        case .ffmpegNotFound:
            "FFmpeg was not found. Install FFmpeg or place ffmpeg in Resources/Tools."
        case let .processFailed(executable, exitCode, summary):
            "\(executable) exited with code \(exitCode). \(summary)"
        case let .exportNotImplemented(message):
            message
        case .previewUnavailable:
            "The first video frame could not be loaded."
        }
    }
}
