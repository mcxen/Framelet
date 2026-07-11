import Foundation

struct EditingProject: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var name: String
    var mediaReference: MediaReference?
    var segments: [Segment]
    var selectedStreams: Set<Int>
    var exportPreset: ExportPreset
    var createdAt: Date
    var modifiedAt: Date

    static func empty(name: String = "Untitled") -> EditingProject {
        EditingProject(
            schemaVersion: currentSchemaVersion,
            id: UUID(),
            name: name,
            mediaReference: nil,
            segments: [],
            selectedStreams: [],
            exportPreset: ExportPreset(),
            createdAt: Date(),
            modifiedAt: Date()
        )
    }
}

struct MediaReference: Codable, Hashable, Sendable {
    var originalPath: String
    var bookmarkData: Data?
    var fileSize: Int64
    var modificationDate: Date
}

struct ExportPreset: Codable, Hashable, Sendable {
    var mode: ExportMode = .separateFiles
    var containerExtension: String = "mov"
    var namingPattern: String = "{source}-{timestamp}-{index}"
    var crop: CropSettings = CropSettings()
    var videoEncode: VideoEncodeSettings = VideoEncodeSettings()
    var metadataOverrides: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ExportMode.self, forKey: .mode) ?? .separateFiles
        containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension) ?? "mov"
        namingPattern = try container.decodeIfPresent(String.self, forKey: .namingPattern) ?? "{source}-{timestamp}-{index}"
        crop = try container.decodeIfPresent(CropSettings.self, forKey: .crop) ?? CropSettings()
        videoEncode = try container.decodeIfPresent(VideoEncodeSettings.self, forKey: .videoEncode) ?? VideoEncodeSettings()
        metadataOverrides = try container.decodeIfPresent([String: String].self, forKey: .metadataOverrides) ?? [:]
    }
}

enum ExportMode: String, Codable, CaseIterable, Sendable {
    case separateFiles
    case mergedFile
}

struct CropSettings: Codable, Hashable, Sendable {
    var isEnabled: Bool = false
    var x: Int = 0
    var y: Int = 0
    var width: Int?
    var height: Int?

    func rectangle(sourceWidth: Int?, sourceHeight: Int?) throws -> CropRectangle? {
        guard isEnabled else { return nil }

        let resolvedWidth = width ?? sourceWidth
        let resolvedHeight = height ?? sourceHeight
        guard let resolvedWidth, let resolvedHeight, resolvedWidth > 0, resolvedHeight > 0 else {
            throw MediaError.invalidCrop
        }

        let maxWidth = sourceWidth ?? resolvedWidth
        let maxHeight = sourceHeight ?? resolvedHeight
        let clampedX = max(0, min(x, max(0, maxWidth - 2)))
        let clampedY = max(0, min(y, max(0, maxHeight - 2)))
        let clampedWidth = max(2, min(resolvedWidth, maxWidth - clampedX))
        let clampedHeight = max(2, min(resolvedHeight, maxHeight - clampedY))

        return CropRectangle(
            x: clampedX.evenForVideo,
            y: clampedY.evenForVideo,
            width: clampedWidth.evenForVideo,
            height: clampedHeight.evenForVideo
        )
    }
}

struct CropRectangle: Codable, Hashable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var ffmpegFilter: String {
        "crop=\(width):\(height):\(x):\(y)"
    }
}

struct VideoEncodeSettings: Codable, Hashable, Sendable {
    var codec: VideoCodec = .h264VideoToolbox
    var bitrateMbps: Int = 12
}

enum VideoCodec: String, Codable, CaseIterable, Sendable {
    case h264VideoToolbox
    case h264Software

    var displayName: String {
        switch self {
        case .h264VideoToolbox:
            "H.264 VideoToolbox"
        case .h264Software:
            "H.264 Software"
        }
    }
}

private extension Int {
    var evenForVideo: Int {
        self - (self % 2)
    }
}
