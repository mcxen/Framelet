import Foundation

protocol WaveformService: Sendable {
    func loadWaveform(from url: URL, startTime: Double, duration: Double, targetSampleCount: Int) async throws -> Waveform
}

struct FFmpegWaveformService: WaveformService {
    private let executableResolver: ToolResolver
    private let commandLog: CommandLog?

    init(executableResolver: ToolResolver = ToolResolver(), commandLog: CommandLog? = nil) {
        self.executableResolver = executableResolver
        self.commandLog = commandLog
    }

    func loadWaveform(from url: URL, startTime: Double, duration: Double, targetSampleCount: Int) async throws -> Waveform {
        guard duration.isFinite, duration > 0 else {
            return Waveform(duration: 0, samples: [])
        }
        guard let executable = executableResolver.resolve("ffmpeg") else {
            throw MediaError.ffmpegNotFound
        }

        let output = try await ProcessRunner.run(
            executableURL: executable,
            arguments: [
                "-hide_banner",
                "-nostdin",
                "-v", "error",
                "-ss", String(format: "%.3f", max(0, startTime)),
                "-i", url.path,
                "-t", String(format: "%.3f", duration),
                "-map", "0:a:0?",
                "-ac", "1",
                "-ar", "8000",
                "-f", "f32le",
                "pipe:1"
            ],
            commandLog: commandLog
        )

        let values = output.stdout.withUnsafeBytes { rawBuffer -> [Float] in
            let floats = rawBuffer.bindMemory(to: Float.self)
            return floats.map { min(1, max(-1, $0.isFinite ? $0 : 0)) }
        }

        guard !values.isEmpty else {
            return Waveform(duration: duration, samples: [])
        }

        let targetCount = max(64, min(targetSampleCount, 2_000))
        let bucketSize = max(1, values.count / targetCount)
        var samples: [WaveformSample] = []
        samples.reserveCapacity(min(targetCount, values.count))

        var index = 0
        while index < values.count {
            let end = min(values.count, index + bucketSize)
            let slice = values[index..<end]
            let minimum = slice.min() ?? 0
            let maximum = slice.max() ?? 0
            let midpoint = Double(index + (end - index) / 2) / Double(values.count)
            samples.append(
                WaveformSample(
                    time: midpoint * duration,
                    minimum: minimum,
                    maximum: maximum
                )
            )
            index = end
        }

        return Waveform(duration: duration, samples: samples)
    }
}
