import Foundation

struct ProcessOutput: Sendable {
    var stdout: Data
    var stderr: Data
    var exitCode: Int32
}

enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        commandLog: CommandLog? = nil
    ) async throws -> ProcessOutput {
        await commandLog?.record(executableURL: executableURL, arguments: arguments)
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let output = ProcessOutput(
                    stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
                    stderr: stderr.fileHandleForReading.readDataToEndOfFile(),
                    exitCode: process.terminationStatus
                )

                if output.exitCode == 0 {
                    continuation.resume(returning: output)
                } else {
                    let summary = String(data: output.stderr, encoding: .utf8)?
                        .split(separator: "\n")
                        .suffix(6)
                        .joined(separator: "\n") ?? ""
                    continuation.resume(
                        throwing: MediaError.processFailed(
                            executable: executableURL.lastPathComponent,
                            exitCode: output.exitCode,
                            summary: summary
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
