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
    static let latestReleaseURL = URL(string: "https://github.com/mcxen/Framelet/releases/latest")!
    static let latestDownloadURL = URL(string: "https://github.com/mcxen/Framelet/releases/latest/download/Framelet-macOS-arm64.zip")!

    private(set) var state: State = .idle
    private var availableVersion: String?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    func check() async {
        state = .checking
        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.httpMethod = "HEAD"
            request.setValue("Framelet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let latestVersion = Self.releaseVersion(from: http.url) else {
                throw UpdateError.releaseUnavailable
            }
            availableVersion = latestVersion
            state = isNewer(latestVersion, than: currentVersion) ? .available(version: latestVersion) : .upToDate
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func install() async {
        guard availableVersion != nil else {
            state = .failed(message: UpdateError.assetUnavailable.localizedDescription)
            return
        }
        do {
            state = .downloading(progress: 0)
            let installedApp = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: installedApp.deletingLastPathComponent().path) else {
                throw UpdateError.installLocationNotWritable
            }
            guard let helper = Bundle.main.url(forAuxiliaryExecutable: "FrameletUpdater") else {
                throw UpdateError.helperUnavailable
            }
            let process = Process()
            process.executableURL = helper
            process.arguments = [
                String(ProcessInfo.processInfo.processIdentifier),
                Self.latestDownloadURL.absoluteString,
                installedApp.path
            ]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    static func releaseVersion(from url: URL?) -> String? {
        guard let url else { return nil }
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else { return nil }
        let version = components[tagIndex + 1]
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return version.isEmpty ? nil : version
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        guard current != "Development" else { return false }
        return candidate.compare(current, options: .numeric) == .orderedDescending
    }

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
