import AVFoundation
import AppKit
import Foundation

protocol ThumbnailService: Sendable {
    func loadThumbnails(from url: URL, startTime: Double, duration: Double, targetCount: Int) async throws -> [TimelineThumbnail]
}

struct AVAssetThumbnailService: ThumbnailService {
    func loadThumbnails(from url: URL, startTime: Double, duration: Double, targetCount: Int) async throws -> [TimelineThumbnail] {
        guard duration.isFinite, duration > 0, targetCount > 0 else { return [] }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 180, height: 110)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        let count = max(1, min(targetCount, 18))
        let safeStartTime = max(0, startTime)
        let step = duration / Double(max(count - 1, 1))
        let times = (0..<count).map { index in
            let displayTime = count == 1 ? 0 : Double(index) * step
            let clampedTime = min(max(0, duration - 0.001), displayTime)
            return CMTime(seconds: safeStartTime + clampedTime, preferredTimescale: 600)
        }

        var thumbnails: [TimelineThumbnail] = []
        for time in times {
            do {
                let result = try await generator.image(at: time)
                let actualTime = result.actualTime.seconds.isFinite ? result.actualTime.seconds : time.seconds
                thumbnails.append(
                    TimelineThumbnail(
                        timestamp: max(0, actualTime - safeStartTime),
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
