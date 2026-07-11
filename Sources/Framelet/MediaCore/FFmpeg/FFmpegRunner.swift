import Foundation

actor FFmpegRunner {
    private let executableResolver: ToolResolver
    private let commandLog: CommandLog?

    init(executableResolver: ToolResolver = ToolResolver(), commandLog: CommandLog? = nil) {
        self.executableResolver = executableResolver
        self.commandLog = commandLog
    }

    func export(_ job: ExportJob) -> AsyncThrowingStream<ExportEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.preparing)
                    guard let ffmpeg = executableResolver.resolve("ffmpeg") else {
                        throw MediaError.ffmpegNotFound
                    }

                    let enabled = job.segments.filter(\.isEnabled)
                    guard !enabled.isEmpty else {
                        throw MediaError.invalidSegmentRange
                    }
                    let totalDuration = enabled.reduce(0) { $0 + $1.duration }
                    guard totalDuration > 0 else {
                        throw MediaError.invalidSegmentRange
                    }

                    switch job.mode {
                    case .separateFiles:
                        var completedDuration = 0.0
                        for (offset, segment) in enabled.enumerated() {
                            let outputURL = outputURL(for: segment, index: offset + 1, job: job)
                            try await exportSegment(
                                segment,
                                index: offset + 1,
                                total: enabled.count,
                                outputURL: outputURL,
                                ffmpeg: ffmpeg,
                                job: job,
                                completedDuration: completedDuration,
                                totalDuration: totalDuration,
                                progressScale: 1,
                                continuation: continuation
                            )
                            completedDuration += segment.duration
                            continuation.yield(.completed(outputURL))
                        }

                    case .mergedFile:
                        let finalURL = mergedOutputURL(for: job)
                        let temporaryDirectory = FileManager.default.temporaryDirectory
                            .appendingPathComponent("Framelet-\(job.id.uuidString)", isDirectory: true)
                        try FileManager.default.createDirectory(
                            at: temporaryDirectory,
                            withIntermediateDirectories: true
                        )
                        defer {
                            try? FileManager.default.removeItem(at: temporaryDirectory)
                        }

                        var temporaryOutputs: [URL] = []
                        var completedDuration = 0.0
                        for (offset, segment) in enabled.enumerated() {
                            let outputURL = temporaryDirectory
                                .appendingPathComponent("segment-\(String(format: "%03d", offset + 1)).\(job.containerExtension)")
                            try await exportSegment(
                                segment,
                                index: offset + 1,
                                total: enabled.count,
                                outputURL: outputURL,
                                ffmpeg: ffmpeg,
                                job: job,
                                completedDuration: completedDuration,
                                totalDuration: totalDuration,
                                progressScale: 0.95,
                                continuation: continuation
                            )
                            completedDuration += segment.duration
                            temporaryOutputs.append(outputURL)
                        }

                        continuation.yield(.concatenating)
                        let listURL = temporaryDirectory.appendingPathComponent("segments.ffconcat")
                        try concatList(for: temporaryOutputs).write(to: listURL, atomically: true, encoding: .utf8)

                        _ = try await ProcessRunner.run(
                            executableURL: ffmpeg,
                            arguments: [
                                "-hide_banner",
                                "-nostdin",
                                "-y",
                                "-f", "concat",
                                "-safe", "0",
                                "-i", listURL.path,
                                "-map_metadata", "0",
                                "-map_metadata:s", "0:s",
                                "-c", "copy",
                                finalURL.path
                            ],
                            commandLog: commandLog
                        )
                        continuation.yield(.progress(fraction: 1, speed: nil))
                        continuation.yield(.completed(finalURL))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func exportSegment(
        _ segment: Segment,
        index: Int,
        total: Int,
        outputURL: URL,
        ffmpeg: URL,
        job: ExportJob,
        completedDuration: Double,
        totalDuration: Double,
        progressScale: Double,
        continuation: AsyncThrowingStream<ExportEvent, Error>.Continuation
    ) async throws {
        guard segment.sourceEnd > segment.sourceStart else {
            throw MediaError.invalidSegmentRange
        }

        continuation.yield(.processingSegment(current: index, total: total))
        let sourceStart = max(0, segment.sourceStart + job.sourceStartOffset)
        var arguments = [
            "-hide_banner",
            "-nostdin",
            "-progress", "pipe:1",
            "-nostats",
            "-y"
        ]

        if job.cropRectangle == nil {
            // Stream-copy exports seek to the preceding keyframe for speed and packet integrity.
            arguments += ["-ss", String(format: "%.3f", sourceStart)]
        }
        arguments += ["-i", job.inputURL.path]
        if job.cropRectangle != nil {
            // A decoded crop can seek frame-accurately after opening the input. This avoids an
            // audio/video timestamp gap that some players render as black frames at the start.
            arguments += ["-ss", String(format: "%.3f", sourceStart)]
        }
        arguments += ["-t", String(format: "%.3f", segment.duration)]

        if job.selectedStreamIndexes.isEmpty {
            arguments += ["-map", "0"]
        } else {
            for streamIndex in job.selectedStreamIndexes.sorted() {
                arguments += ["-map", "0:\(streamIndex)"]
            }
        }

        // Copy container and per-stream tags from the source, then apply explicit user edits.
        arguments += ["-map_metadata", "0", "-map_metadata:s", "0:s"]
        for (key, value) in job.metadataOverrides.sorted(by: { $0.key < $1.key }) {
            arguments += ["-metadata", "\(key)=\(value)"]
        }
        arguments += codecArguments(for: job)
        if job.cropRectangle != nil {
            arguments += ["-reset_timestamps", "1"]
        }
        arguments += ["-avoid_negative_ts", "make_zero", outputURL.path]

        let progressParser = FFmpegProgressParser()
        _ = try await ProcessRunner.run(
            executableURL: ffmpeg,
            arguments: arguments,
            commandLog: commandLog
        ) { data in
            for elapsed in progressParser.consume(data) {
                let segmentProgress = min(max(elapsed, 0), segment.duration)
                let fraction = progressScale * (completedDuration + segmentProgress) / totalDuration
                continuation.yield(.progress(fraction: min(max(fraction, 0), progressScale), speed: nil))
            }
        }
        let completedFraction = progressScale * (completedDuration + segment.duration) / totalDuration
        continuation.yield(.progress(fraction: min(completedFraction, progressScale), speed: nil))
    }

    private func outputURL(for segment: Segment, index: Int, job: ExportJob) -> URL {
        let filename = resolvedName(
            pattern: job.namingPattern,
            segmentName: segment.name,
            index: index,
            baseName: job.baseName,
            sourceBaseName: job.sourceBaseName,
            timestamp: filenameTimestamp(job.exportTimestamp),
            extension: job.containerExtension
        )
        return availableOutputURL(job.outputDirectory.appendingPathComponent(filename))
    }

    private func mergedOutputURL(for job: ExportJob) -> URL {
        let sourceBase = job.sourceBaseName.isEmpty
            ? job.inputURL.deletingPathExtension().lastPathComponent
            : job.sourceBaseName
        let safeBase = sanitize(sourceBase)
        return availableOutputURL(job.outputDirectory.appendingPathComponent(
            "\(safeBase)-\(filenameTimestamp(job.exportTimestamp))-merged.\(job.containerExtension)"
        ))
    }

    private func availableOutputURL(_ proposed: URL) -> URL {
        guard FileManager.default.fileExists(atPath: proposed.path) else { return proposed }
        let directory = proposed.deletingLastPathComponent()
        let stem = proposed.deletingPathExtension().lastPathComponent
        let pathExtension = proposed.pathExtension
        for suffix in 2...9_999 {
            let candidate = directory.appendingPathComponent("\(stem)-\(suffix).\(pathExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString).\(pathExtension)")
    }

    private func resolvedName(
        pattern: String,
        segmentName: String,
        index: Int,
        baseName: String,
        sourceBaseName: String,
        timestamp: String,
        extension pathExtension: String
    ) -> String {
        let fallback = "{source}-{timestamp}-{index}"
        let selectedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : pattern
        let stem = selectedPattern
            .replacingOccurrences(of: "{index}", with: String(format: "%03d", index))
            .replacingOccurrences(of: "{name}", with: segmentName)
            .replacingOccurrences(of: "{project}", with: baseName)
            .replacingOccurrences(of: "{source}", with: sourceBaseName)
            .replacingOccurrences(of: "{timestamp}", with: timestamp)
        return "\(sanitize(stem)).\(pathExtension)"
    }

    private func filenameTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func concatList(for urls: [URL]) -> String {
        let entries = urls
            .map { "file '\(escapeConcatPath($0.path))'" }
            .joined(separator: "\n")
        return "ffconcat version 1.0\n\(entries)\n"
    }

    private func escapeConcatPath(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func codecArguments(for job: ExportJob) -> [String] {
        guard let cropRectangle = job.cropRectangle else {
            return ["-c", "copy"]
        }

        var arguments = [
            "-vf", cropRectangle.ffmpegFilter,
            "-c:a", "copy",
            "-c:s", "copy",
            "-c:d", "copy"
        ]

        switch job.videoEncode.codec {
        case .h264VideoToolbox:
            arguments += [
                "-c:v", "h264_videotoolbox",
                "-b:v", "\(job.videoEncode.bitrateMbps)M",
                "-allow_sw", "1"
            ]
        case .h264Software:
            arguments += [
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-crf", "18"
            ]
        }

        return arguments
    }
}

final class FFmpegProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func consume(_ data: Data) -> [Double] {
        lock.lock()
        defer { lock.unlock() }

        buffer += String(decoding: data, as: UTF8.self)
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        buffer = String(lines.last ?? "")

        return lines.dropLast().compactMap { line in
            guard line.hasPrefix("out_time_us="),
                  let microseconds = Double(line.dropFirst("out_time_us=".count)),
                  microseconds.isFinite else { return nil }
            return microseconds / 1_000_000
        }
    }
}
