import AppKit
import Foundation

struct TimelineThumbnail: Identifiable, @unchecked Sendable {
    var id: Double { timestamp }
    var timestamp: Double
    var image: NSImage
}
