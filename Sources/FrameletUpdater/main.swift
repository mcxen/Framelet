import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FrameletUpdater: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
 guard arguments.count == 4 else {
    fail("usage: FrameletUpdater <pid> <downloaded-app> <installed-app>")
}

guard let pid = Int32(arguments[1]) else { fail("invalid process id") }
let source = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let destination = URL(fileURLWithPath: arguments[3]).standardizedFileURL
let fileManager = FileManager.default

// Only replace a real Framelet application with another Framelet application.
guard destination.pathExtension == "app", destination.lastPathComponent == "Framelet.app",
      source.pathExtension == "app", source.lastPathComponent == "Framelet.app",
      fileManager.fileExists(atPath: source.appending(path: "Contents/MacOS/Framelet").path) else {
    fail("invalid application paths")
}

for _ in 0..<300 where kill(pid, 0) == 0 {
    Thread.sleep(forTimeInterval: 0.1)
}
if kill(pid, 0) == 0 { fail("application did not quit") }

let parent = destination.deletingLastPathComponent()
let backup = parent.appending(path: ".Framelet.previous.app")
do {
    if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
    if fileManager.fileExists(atPath: destination.path) { try fileManager.moveItem(at: destination, to: backup) }
    do {
        try fileManager.moveItem(at: source, to: destination)
    } catch {
        if fileManager.fileExists(atPath: backup.path) {
            try? fileManager.moveItem(at: backup, to: destination)
        }
        throw error
    }
    try? fileManager.removeItem(at: backup)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [destination.path]
    try process.run()
} catch {
    fail(error.localizedDescription)
}
