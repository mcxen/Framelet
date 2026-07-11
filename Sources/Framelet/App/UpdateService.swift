import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(progress: Double)
        case failed(message: String)
    }

    static let shared = UpdateService()
    private(set) var state: State = .idle
    private var release: GitHubRelease?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    func check() async {
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/mcxen/Framelet/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Framelet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.releaseUnavailable
            }
            let latest = try JSONDecoder().decode(GitHubRelease.self, from: data)
            release = latest
            let latestVersion = latest.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            state = isNewer(latestVersion, than: currentVersion) ? .available(version: latestVersion) : .upToDate
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func install() async {
        guard let release,
              let asset = release.assets.first(where: { $0.name.hasSuffix("macOS-arm64.zip") }) else {
            state = .failed(message: UpdateError.assetUnavailable.localizedDescription)
            return
        }
        do {
            state = .downloading(progress: 0)
            let (temporaryDownload, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.downloadFailed }
            state = .downloading(progress: 0.7)

            let work = FileManager.default.temporaryDirectory.appending(path: "FrameletUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let archive = work.appending(path: asset.name)
            try FileManager.default.moveItem(at: temporaryDownload, to: archive)
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
            let newApp = work.appending(path: "Framelet.app")
            guard FileManager.default.fileExists(atPath: newApp.appending(path: "Contents/MacOS/Framelet").path) else {
                throw UpdateError.invalidArchive
            }

            let installedApp = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: installedApp.deletingLastPathComponent().path) else {
                throw UpdateError.installLocationNotWritable
            }
            guard let helper = Bundle.main.url(forAuxiliaryExecutable: "FrameletUpdater") else {
                throw UpdateError.helperUnavailable
            }
            let process = Process()
            process.executableURL = helper
            process.arguments = [String(ProcessInfo.processInfo.processIdentifier), newApp.path, installedApp.path]
            try process.run()
            state = .downloading(progress: 1)
            NSApp.terminate(nil)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        guard current != "Development" else { return false }
        return candidate.compare(current, options: .numeric) == .orderedDescending
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.invalidArchive }
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
    }
    let tagName: String
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case assets }
}

private enum UpdateError: LocalizedError {
    case releaseUnavailable, assetUnavailable, downloadFailed, invalidArchive, helperUnavailable, installLocationNotWritable
    var errorDescription: String? {
        switch self {
        case .releaseUnavailable: "Unable to load the latest GitHub release."
        case .assetUnavailable: "The latest release has no compatible macOS download."
        case .downloadFailed: "The update download failed."
        case .invalidArchive: "The downloaded update is invalid."
        case .helperUnavailable: "The update helper is missing. Please reinstall Framelet."
        case .installLocationNotWritable: "Framelet cannot update this installation location. Move it to your Applications folder or update with Homebrew."
        }
    }
}
