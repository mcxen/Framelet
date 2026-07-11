import Foundation

protocol MediaProbeService: Sendable {
    func probe(_ url: URL) async throws -> MediaInfo
}
