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
        commandLog: CommandLog? = nil,
        onStandardOutput: (@Sendable (Data) -> Void)? = nil
    ) async throws -> ProcessOutput {
        await commandLog?.record(executableURL: executableURL, arguments: arguments)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let state = ProcessState(executable: executableURL.lastPathComponent, continuation: continuation)

                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = stdout
                process.standardError = stderr

                process.terminationHandler = { process in
                    state.setExitCode(process.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    stdout.fileHandleForReading.closeFile()
                    stderr.fileHandleForReading.closeFile()
                    state.fail(error)
                    return
                }

                // Drain both pipes concurrently while the child is running. Waiting for process
                // termination before reading can deadlock once either kernel pipe buffer fills.
                DispatchQueue.global(qos: .utility).async {
                    var data = Data()
                    while true {
                        let chunk = stdout.fileHandleForReading.readData(ofLength: 64 * 1_024)
                        guard !chunk.isEmpty else { break }
                        data.append(chunk)
                        onStandardOutput?(chunk)
                    }
                    state.setStdout(data)
                }
                DispatchQueue.global(qos: .utility).async {
                    state.setStderr(stderr.fileHandleForReading.readDataToEndOfFile())
                }
            }
        } onCancel: {
            // Process lifetime is also bounded by FFmpeg's own operation. Cancellation-aware
            // process ownership will be added where long-running jobs expose a Cancel action.
        }
    }
}

private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private let executable: String
    private var continuation: CheckedContinuation<ProcessOutput, Error>?
    private var stdout: Data?
    private var stderr: Data?
    private var exitCode: Int32?

    init(executable: String, continuation: CheckedContinuation<ProcessOutput, Error>) {
        self.executable = executable
        self.continuation = continuation
    }

    func setStdout(_ data: Data) { update { stdout = data } }
    func setStderr(_ data: Data) { update { stderr = data } }
    func setExitCode(_ code: Int32) { update { exitCode = code } }

    func fail(_ error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    private func update(_ mutation: () -> Void) {
        lock.lock()
        mutation()
        guard let stdout, let stderr, let exitCode, let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        let output = ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
        if exitCode == 0 {
            continuation.resume(returning: output)
        } else {
            let summary = String(data: stderr, encoding: .utf8)?
                .split(separator: "\n")
                .suffix(6)
                .joined(separator: "\n") ?? ""
            continuation.resume(
                throwing: MediaError.processFailed(
                    executable: executable,
                    exitCode: exitCode,
                    summary: summary
                )
            )
        }
    }
}
