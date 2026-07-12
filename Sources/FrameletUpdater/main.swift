import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FrameletUpdater: \(message)\n".utf8))
    exit(1)
}

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "FrameletUpdater", code: Int(process.terminationStatus))
    }
}

private func reopen(_ application: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [application.path]
    try? process.run()
}

let arguments = CommandLine.arguments
 guard arguments.count == 4 else {
    fail("usage: FrameletUpdater <pid> <download-url> <installed-app>")
}

guard let pid = Int32(arguments[1]) else { fail("invalid process id") }
guard let downloadURL = URL(string: arguments[2]),
      downloadURL.scheme == "https",
      downloadURL.host == "github.com",
      downloadURL.path == "/mcxen/Framelet/releases/latest/download/Framelet-macOS-arm64.zip" else {
    fail("invalid download URL")
}
let destination = URL(fileURLWithPath: arguments[3]).standardizedFileURL
let fileManager = FileManager.default

guard destination.pathExtension == "app", destination.lastPathComponent == "Framelet.app" else {
    fail("invalid application path")
}

let work = fileManager.temporaryDirectory.appending(path: "FrameletUpdate-\(UUID().uuidString)")
let archive = work.appending(path: "Framelet-macOS-arm64.zip")

do {
    try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var downloadError: Error?
    let task = URLSession.shared.downloadTask(with: downloadURL) { temporaryURL, response, error in
        defer { semaphore.signal() }
        if let error {
            downloadError = error
            return
        }
        guard let temporaryURL,
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            downloadError = NSError(domain: "FrameletUpdater", code: 1)
            return
        }
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: archive)
        } catch {
            downloadError = error
        }
    }
    task.resume()
    semaphore.wait()
    if let downloadError { throw downloadError }

    try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
    let source = work.appending(path: "Framelet.app")
    guard fileManager.fileExists(atPath: source.appending(path: "Contents/MacOS/Framelet").path) else {
        throw NSError(domain: "FrameletUpdater", code: 2)
    }

    for _ in 0..<300 where kill(pid, 0) == 0 {
        Thread.sleep(forTimeInterval: 0.1)
    }
    if kill(pid, 0) == 0 {
        throw NSError(domain: "FrameletUpdater", code: 3)
    }

    let parent = destination.deletingLastPathComponent()
    let backup = parent.appending(path: ".Framelet.previous.app")
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
    try? fileManager.removeItem(at: work)
    reopen(destination)
} catch {
    try? fileManager.removeItem(at: work)
    reopen(destination)
    fail(error.localizedDescription)
}
