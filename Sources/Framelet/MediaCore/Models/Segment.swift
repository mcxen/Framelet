import Foundation

struct Segment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sourceStart: Double
    var sourceEnd: Double
    var isEnabled: Bool
    var colorTag: SegmentColor?

    var duration: Double {
        max(0, sourceEnd - sourceStart)
    }

    init(
        id: UUID = UUID(),
        name: String,
        sourceStart: Double,
        sourceEnd: Double,
        isEnabled: Bool = true,
        colorTag: SegmentColor? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.isEnabled = isEnabled
        self.colorTag = colorTag
    }
}

enum SegmentColor: String, Codable, CaseIterable, Sendable {
    case blue
    case green
    case yellow
    case orange
    case red
    case purple
}
