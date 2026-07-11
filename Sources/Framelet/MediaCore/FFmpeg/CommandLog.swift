import Foundation

struct CommandLogEntry: Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var command: String
    var exitCode: Int32?
}

actor CommandLog {
    private var entries: [CommandLogEntry] = []
    private let limit: Int

    init(limit: Int = 40) {
        self.limit = limit
    }

    func record(executableURL: URL, arguments: [String], exitCode: Int32? = nil) {
        entries.insert(
            CommandLogEntry(
                date: Date(),
                command: Self.commandLine(executableURL: executableURL, arguments: arguments),
                exitCode: exitCode
            ),
            at: 0
        )

        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    func snapshot() -> [CommandLogEntry] {
        entries
    }

    func clear() {
        entries.removeAll()
    }

    private static func commandLine(executableURL: URL, arguments: [String]) -> String {
        ([executableURL.path] + arguments)
            .map(shellQuote)
            .joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=.,/:@%")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
