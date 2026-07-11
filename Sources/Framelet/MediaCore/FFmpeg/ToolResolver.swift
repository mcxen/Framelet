import Foundation

struct ToolResolver: Sendable {
    func resolve(_ name: String) -> URL? {
        let local = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Tools")
        if let local, FileManager.default.isExecutableFile(atPath: local.path) {
            return local
        }

        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
