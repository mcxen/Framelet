import CryptoKit
import Foundation

struct ProxyBuildResult: Sendable {
    var url: URL
    var reusedExistingFile: Bool
}

protocol ProxyBuilder: Sendable {
    func buildProxy(for media: MediaReference) async throws -> ProxyBuildResult
}

struct FFmpegProxyBuilder: ProxyBuilder {
    private let executableResolver: ToolResolver
    private let commandLog: CommandLog?

    init(executableResolver: ToolResolver = ToolResolver(), commandLog: CommandLog? = nil) {
        self.executableResolver = executableResolver
        self.commandLog = commandLog
    }

    func buildProxy(for media: MediaReference) async throws -> ProxyBuildResult {
        guard let executable = executableResolver.resolve("ffmpeg") else {
            throw MediaError.ffmpegNotFound
        }

        let proxyURL = try proxyURL(for: media)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: proxyURL.path) {
            return ProxyBuildResult(url: proxyURL, reusedExistingFile: true)
        }

        try fileManager.createDirectory(
            at: proxyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let partialURL = proxyURL.appendingPathExtension("partial")
        try? fileManager.removeItem(at: partialURL)

        _ = try await ProcessRunner.run(
            executableURL: executable,
            arguments: [
                "-hide_banner",
                "-nostdin",
                "-y",
                "-i", media.originalPath,
                "-map", "0:v:0",
                "-map", "0:a:0?",
                "-vf", "scale=1280:1280:flags=lanczos:force_original_aspect_ratio=decrease:force_divisible_by=2:in_color_matrix=auto:in_range=auto:out_color_matrix=bt709:out_range=tv,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709,format=yuv420p",
                "-c:v", "h264_videotoolbox",
                "-b:v", "5M",
                "-allow_sw", "1",
                "-c:a", "aac",
                "-movflags", "+faststart",
                partialURL.path
            ],
            commandLog: commandLog
        )

        try? fileManager.removeItem(at: proxyURL)
        try fileManager.moveItem(at: partialURL, to: proxyURL)
        return ProxyBuildResult(url: proxyURL, reusedExistingFile: false)
    }

    private func proxyURL(for media: MediaReference) throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Framelet/Proxies", isDirectory: true)

        let key = [
            media.originalPath,
            String(media.fileSize),
            String(media.modificationDate.timeIntervalSince1970),
            "proxy-v1-h264-1280"
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent("\(name).mp4")
    }
}
