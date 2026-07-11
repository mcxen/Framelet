import AppKit
import Foundation

struct TimelineThumbnail: Identifiable {
    var id: Double { timestamp }
    var timestamp: Double
    var image: NSImage
}
