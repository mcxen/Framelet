import AVFoundation
import AppKit
import Foundation

protocol ThumbnailService: Sendable {
    func loadThumbnails(from url: URL, duration: Double, targetCount: Int) async throws -> [TimelineThumbnail]
}

struct AVAssetThumbnailService: ThumbnailService {
    func loadThumbnails(from url: URL, duration: Double, targetCount: Int) async throws -> [TimelineThumbnail] {
        guard duration.isFinite, duration > 0, targetCount > 0 else { return [] }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 180, height: 110)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        let count = max(1, min(targetCount, 18))
        let step = duration / Double(count)
        let times = (0..<count).map { index in
            CMTime(seconds: min(duration, (Double(index) + 0.5) * step), preferredTimescale: 600)
        }

        var thumbnails: [TimelineThumbnail] = []
        for time in times {
            do {
                let result = try await generator.image(at: time)
                thumbnails.append(
                    TimelineThumbnail(
                        timestamp: result.actualTime.seconds.isFinite ? result.actualTime.seconds : time.seconds,
                        image: NSImage(cgImage: result.image, size: .zero)
                    )
                )
            } catch {
                continue
            }
        }

        return thumbnails.sorted { $0.timestamp < $1.timestamp }
    }
}
