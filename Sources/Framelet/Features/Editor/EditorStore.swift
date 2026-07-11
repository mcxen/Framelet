import AppKit
import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class EditorStore {
    var project: EditingProject
    var mediaInfo: MediaInfo?
    var player = AVPlayer()
    var currentTime: Double = 0
    var duration: Double = 0
    var inPoint: Double?
    var outPoint: Double?
    var selectedSegmentID: Segment.ID?
    var isPlaying = false
    var isLoading = false
    var statusMessage = "Open a video or audio file to begin."
    var errorMessage: String?
    var projectURL: URL?
    var showInspector = true
    var selectedInspectorTab: InspectorTab = .segments
    var exportEvents: [String] = []
    var keyframeIndex = KeyframeIndex([])
    var isLoadingKeyframes = false
    var thumbnails: [TimelineThumbnail] = []
    var isLoadingThumbnails = false
    var waveform = Waveform(duration: 0, samples: [])
    var isLoadingWaveform = false
    var proxyURL: URL?
    var isUsingProxy = false
    var isBuildingProxy = false
    var commandLogEntries: [CommandLogEntry] = []
    var timelineVisibleStart: Double = 0
    var timelineVisibleDuration: Double = 1

    private let services: AppServices
    private var timeObserver: Any?

    init(project: EditingProject = .empty(), services: AppServices) {
        self.project = project
        self.services = services
        installTimeObserver()
    }

    var mediaURL: URL? {
        guard let path = project.mediaReference?.originalPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var selectedSegment: Segment? {
        guard let selectedSegmentID else { return nil }
        return project.segments.first { $0.id == selectedSegmentID }
    }

    var enabledSegmentsDuration: Double {
        project.segments.filter(\.isEnabled).reduce(0) { $0 + $1.duration }
    }

    var timelineZoom: Double {
        guard duration > 0, timelineVisibleDuration > 0 else { return 1 }
        return max(1, duration / timelineVisibleDuration)
    }

    var selectedSegmentKeyframeDiagnostics: SegmentKeyframeDiagnostics? {
        guard let selectedSegment else { return nil }
        return diagnostics(for: selectedSegment)
    }

    func openMedia(_ url: URL) {
        Task {
            await loadMedia(url)
        }
    }

    @discardableResult
    func openDroppedItems(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: { $0.isFileURL }) else { return false }

        if url.pathExtension.lowercased() == services.projectStore.fileExtension.lowercased() {
            openProject(url)
        } else {
            openMedia(url)
        }
        return true
    }

    func openProject(_ url: URL) {
        Task {
            do {
                isLoading = true
                defer { isLoading = false }
                project = try services.projectStore.load(from: url)
                projectURL = url
                if let mediaURL {
                    await loadMedia(mediaURL, replacingProject: false)
                }
                statusMessage = "Opened \(url.lastPathComponent)"
            } catch {
                present(error)
            }
        }
    }

    func saveProject(to url: URL? = nil) {
        do {
            let targetURL = try url ?? chooseProjectSaveURL()
            try services.projectStore.save(project, to: targetURL)
            projectURL = targetURL
            statusMessage = "Saved \(targetURL.lastPathComponent)"
        } catch {
            present(error)
        }
    }

    func importSegmentsFromCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = csvContentTypes
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported = try SegmentCSV.decode(text, duration: duration > 0 ? duration : nil)
            guard !imported.isEmpty else {
                statusMessage = "No segments found in \(url.lastPathComponent)"
                return
            }

            project.segments.append(contentsOf: imported)
            selectedSegmentID = imported.first?.id
            selectedInspectorTab = .segments
            project.modifiedAt = Date()
            statusMessage = "Imported \(imported.count) segments from \(url.lastPathComponent)"
        } catch {
            present(error)
        }
    }

    func exportSegmentsToCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = csvContentTypes
        panel.nameFieldStringValue = "\(project.name)-segments.csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try SegmentCSV.encode(project.segments).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported \(project.segments.count) segments to \(url.lastPathComponent)"
        } catch {
            present(error)
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        keepTimeVisible(clamped)
    }

    func step(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func stepFrame(direction: Int) {
        guard direction != 0 else { return }
        player.pause()
        isPlaying = false
        if direction > 0 {
            player.currentItem?.step(byCount: direction)
        } else {
            let frameDuration = 1 / max(mediaInfo?.videoStreams.first?.frameRate ?? 30, 1)
            seek(to: currentTime + Double(direction) * frameDuration)
        }
    }

    func jumpToPreviousKeyframe() {
        if let timestamp = keyframeIndex.timestamps.last(where: { $0 < currentTime - 0.001 }) {
            seek(to: timestamp)
        }
    }

    func jumpToNextKeyframe() {
        if let timestamp = keyframeIndex.timestamps.first(where: { $0 > currentTime + 0.001 }) {
            seek(to: timestamp)
        }
    }

    func setInPoint() {
        inPoint = currentTime
        statusMessage = "In point set at \(TimecodeFormatter.string(from: currentTime))"
    }

    func setOutPoint() {
        outPoint = currentTime
        statusMessage = "Out point set at \(TimecodeFormatter.string(from: currentTime))"
    }

    func createSegmentFromMarks() {
        let start = inPoint ?? currentTime
        let end = outPoint ?? min(duration, currentTime + 5)
        createSegment(start: start, end: end)
    }

    func createSegment(start: Double, end: Double) {
        guard end > start else {
            present(MediaError.invalidSegmentRange)
            return
        }

        let segment = Segment(
            name: "Segment \(project.segments.count + 1)",
            sourceStart: start,
            sourceEnd: end
        )
        project.segments.append(segment)
        selectedSegmentID = segment.id
        project.modifiedAt = Date()
        statusMessage = "Created \(segment.name)"
    }

    func deleteSelectedSegment() {
        guard let selectedSegmentID else { return }
        project.segments.removeAll { $0.id == selectedSegmentID }
        self.selectedSegmentID = project.segments.first?.id
        project.modifiedAt = Date()
    }

    func updateSelectedSegment(_ edit: (inout Segment) -> Void) {
        guard let selectedSegmentID,
              let index = project.segments.firstIndex(where: { $0.id == selectedSegmentID }) else { return }
        edit(&project.segments[index])
        project.modifiedAt = Date()
    }

    func updateSegment(id: Segment.ID, start: Double? = nil, end: Double? = nil) {
        guard let index = project.segments.firstIndex(where: { $0.id == id }) else { return }
        let minimumDuration = 0.05
        let old = project.segments[index]
        let newStart = max(0, min(start ?? old.sourceStart, (end ?? old.sourceEnd) - minimumDuration))
        let newEnd = min(duration, max(end ?? old.sourceEnd, newStart + minimumDuration))
        project.segments[index].sourceStart = newStart
        project.segments[index].sourceEnd = newEnd
        selectedSegmentID = id
        project.modifiedAt = Date()
        statusMessage = "\(project.segments[index].name) \(TimecodeFormatter.string(from: newStart)) – \(TimecodeFormatter.string(from: newEnd))"
    }

    func moveSegment(id: Segment.ID, to proposedIndex: Int) {
        guard let currentIndex = project.segments.firstIndex(where: { $0.id == id }) else { return }
        let segment = project.segments.remove(at: currentIndex)
        let adjustedIndex = proposedIndex > currentIndex ? proposedIndex - 1 : proposedIndex
        let targetIndex = max(0, min(adjustedIndex, project.segments.count))
        project.segments.insert(segment, at: targetIndex)
        selectedSegmentID = id
        project.modifiedAt = Date()
        statusMessage = "Moved \(segment.name)"
    }

    func exportSeparateSegments(to outputDirectory: URL? = nil) {
        guard let mediaURL else {
            present(MediaError.missingMedia)
            return
        }

        let resolvedOutputDirectory: URL
        if let outputDirectory {
            resolvedOutputDirectory = outputDirectory
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = mediaURL.deletingLastPathComponent()
            panel.prompt = "Export"
            guard panel.runModal() == .OK, let selectedDirectory = panel.url else { return }
            resolvedOutputDirectory = selectedDirectory
        }

        let cropRectangle: CropRectangle?
        do {
            cropRectangle = try project.exportPreset.crop.rectangle(
                sourceWidth: mediaInfo?.videoStreams.first?.width,
                sourceHeight: mediaInfo?.videoStreams.first?.height
            )
        } catch {
            present(error)
            return
        }

        let requestedContainer = project.exportPreset.containerExtension
        let containerExtension = resolvedExportContainerExtension(requested: requestedContainer)
        var initialExportEvents: [String] = []
        if containerExtension != requestedContainer {
            initialExportEvents.append("Using \(containerExtension.uppercased()) because \(requestedContainer.uppercased()) cannot stream-copy this video codec.")
            project.exportPreset.containerExtension = containerExtension
        }

        let job = ExportJob(
            inputURL: mediaURL,
            outputDirectory: resolvedOutputDirectory,
            segments: project.segments,
            selectedStreamIndexes: project.selectedStreams,
            mode: project.exportPreset.mode,
            containerExtension: containerExtension,
            namingPattern: project.exportPreset.namingPattern,
            baseName: project.name,
            sourceBaseName: mediaURL.deletingPathExtension().lastPathComponent,
            cropRectangle: cropRectangle,
            videoEncode: project.exportPreset.videoEncode
        )

        Task {
            exportEvents = initialExportEvents
            do {
                for try await event in await services.ffmpegRunner.export(job) {
                    handleExportEvent(event)
                }
                refreshCommandLog()
                statusMessage = "Export finished"
            } catch {
                refreshCommandLog()
                present(error)
            }
        }
    }

    func quickExportBesideOriginal() {
        guard let mediaURL else {
            present(MediaError.missingMedia)
            return
        }
        exportSeparateSegments(to: mediaURL.deletingLastPathComponent())
    }

    func buildAndUseProxy() {
        guard let reference = project.mediaReference else {
            present(MediaError.missingMedia)
            return
        }

        Task {
            isBuildingProxy = true
            statusMessage = "Building preview proxy"
            defer { isBuildingProxy = false }

            do {
                let result = try await services.proxies.buildProxy(for: reference)
                proxyURL = result.url
                useProxyPreview(result.url)
                refreshCommandLog()
                statusMessage = result.reusedExistingFile ? "Using cached proxy preview" : "Proxy preview ready"
            } catch {
                refreshCommandLog()
                present(error)
            }
        }
    }

    func refreshCommandLog() {
        Task {
            commandLogEntries = await services.commandLog.snapshot()
        }
    }

    func clearCommandLog() {
        Task {
            await services.commandLog.clear()
            commandLogEntries = []
        }
    }

    func copyCommandToClipboard(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        statusMessage = "Copied FFmpeg command"
    }

    func zoomTimeline(by factor: Double) {
        guard duration > 0, factor > 0 else { return }
        let currentVisibleDuration = min(max(timelineVisibleDuration, 0.1), duration)
        let newVisibleDuration = min(duration, max(0.25, currentVisibleDuration / factor))
        centerTimeline(on: currentTime, visibleDuration: newVisibleDuration)
    }

    func fitTimeline() {
        timelineVisibleStart = 0
        timelineVisibleDuration = max(duration, 1)
    }

    func panTimeline(by fraction: Double) {
        guard duration > 0 else { return }
        let delta = timelineVisibleDuration * fraction
        timelineVisibleStart = clampedTimelineStart(timelineVisibleStart + delta, visibleDuration: timelineVisibleDuration)
    }

    func useOriginalPreview() {
        guard let mediaURL else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: mediaURL))
        isUsingProxy = false
        statusMessage = "Using original media for preview"
    }

    func chooseAndOpenMedia() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            openMedia(url)
        }
    }

    func chooseAndOpenProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = projectContentTypes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            openProject(url)
        }
    }

    private func loadMedia(_ url: URL, replacingProject: Bool = true) async {
        do {
            isLoading = true
            defer { isLoading = false }
            let reference = try services.fileAccess.makeReference(for: url)
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            statusMessage = "Opening \(url.lastPathComponent)…"

            let assetDuration = try? await item.asset.load(.duration).seconds
            if let assetDuration, assetDuration.isFinite {
                duration = assetDuration
                timelineVisibleDuration = max(assetDuration, 1)
            }

            let info = try await services.mediaProbe.probe(url)
            mediaInfo = info
            duration = info.duration ?? assetDuration ?? 0
            timelineVisibleStart = 0
            timelineVisibleDuration = max(duration, 1)
            currentTime = 0
            inPoint = nil
            outPoint = nil
            keyframeIndex = KeyframeIndex([])
            thumbnails = []
            waveform = Waveform(duration: 0, samples: [])
            proxyURL = nil
            isUsingProxy = false

            if replacingProject {
                project = EditingProject.empty(name: url.deletingPathExtension().lastPathComponent)
                project.mediaReference = reference
                project.selectedStreams = Set(info.streams.map(\.index))
                project.exportPreset.containerExtension = defaultContainerExtension(for: info, mediaURL: url)
                if let video = info.videoStreams.first, let width = video.width, let height = video.height {
                    project.exportPreset.crop.width = width
                    project.exportPreset.crop.height = height
                }
                selectedSegmentID = nil
                projectURL = nil
            }

            statusMessage = "Loaded \(url.lastPathComponent) — set In and Out points to create a segment"
            loadKeyframes(for: url, mediaInfo: info)
            loadThumbnails(for: url, duration: duration, mediaInfo: info)
            loadWaveform(for: url, duration: duration, mediaInfo: info)
        } catch {
            present(error)
        }
    }

    private func loadKeyframes(for url: URL, mediaInfo: MediaInfo) {
        guard mediaInfo.videoStreams.first != nil else {
            keyframeIndex = KeyframeIndex([])
            return
        }

        Task {
            isLoadingKeyframes = true
            defer { isLoadingKeyframes = false }

            do {
                keyframeIndex = try await services.keyframes.loadKeyframes(from: url, streamIndex: 0)
                if keyframeIndex.timestamps.isEmpty {
                    statusMessage = "Loaded media; no keyframes reported"
                } else {
                    statusMessage = "Loaded \(keyframeIndex.timestamps.count) keyframes"
                }
            } catch {
                keyframeIndex = KeyframeIndex([])
                exportEvents.append("Keyframe scan failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
    }

    private func loadWaveform(for url: URL, duration: Double, mediaInfo: MediaInfo) {
        guard !mediaInfo.audioStreams.isEmpty else {
            waveform = Waveform(duration: duration, samples: [])
            return
        }

        Task {
            isLoadingWaveform = true
            defer { isLoadingWaveform = false }

            do {
                waveform = try await services.waveforms.loadWaveform(
                    from: url,
                    duration: duration,
                    targetSampleCount: 900
                )
            } catch {
                waveform = Waveform(duration: duration, samples: [])
                exportEvents.append("Waveform generation failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
    }

    private func loadThumbnails(for url: URL, duration: Double, mediaInfo: MediaInfo) {
        guard !mediaInfo.videoStreams.isEmpty else {
            thumbnails = []
            return
        }

        Task {
            isLoadingThumbnails = true
            defer { isLoadingThumbnails = false }

            do {
                thumbnails = try await services.thumbnails.loadThumbnails(
                    from: url,
                    duration: duration,
                    targetCount: 14
                )
            } catch {
                thumbnails = []
                exportEvents.append("Thumbnail generation failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
    }

    private func useProxyPreview(_ url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        isUsingProxy = true
        seek(to: currentTime)
    }

    private func keepTimeVisible(_ time: Double) {
        guard timelineVisibleDuration < duration else { return }
        if time < timelineVisibleStart {
            timelineVisibleStart = clampedTimelineStart(time, visibleDuration: timelineVisibleDuration)
        } else if time > timelineVisibleStart + timelineVisibleDuration {
            timelineVisibleStart = clampedTimelineStart(time - timelineVisibleDuration, visibleDuration: timelineVisibleDuration)
        }
    }

    private func centerTimeline(on time: Double, visibleDuration: Double) {
        timelineVisibleDuration = min(max(visibleDuration, 0.25), max(duration, 1))
        timelineVisibleStart = clampedTimelineStart(time - timelineVisibleDuration / 2, visibleDuration: timelineVisibleDuration)
    }

    private func clampedTimelineStart(_ start: Double, visibleDuration: Double) -> Double {
        max(0, min(start, max(0, duration - visibleDuration)))
    }

    private func chooseProjectSaveURL() throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = projectContentTypes
        panel.nameFieldStringValue = "\(project.name).\(services.projectStore.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw CocoaError(.userCancelled)
        }
        return url
    }

    private var projectContentTypes: [UTType] {
        [UTType(filenameExtension: services.projectStore.fileExtension) ?? .json]
    }

    private var csvContentTypes: [UTType] {
        [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
    }

    private func resolvedExportContainerExtension(requested: String) -> String {
        let normalized = requested.lowercased()
        guard normalized == "mov",
              project.exportPreset.crop.isEnabled == false,
              selectedVideoStreamsContain(codec: "av1") else {
            return normalized
        }
        return "mp4"
    }

    private func defaultContainerExtension(for mediaInfo: MediaInfo, mediaURL: URL) -> String {
        if mediaInfo.videoStreams.contains(where: { $0.codecName?.lowercased() == "av1" }) {
            return "mp4"
        }

        let sourceExtension = mediaURL.pathExtension.lowercased()
        if ["mov", "mp4", "mkv", "m4a"].contains(sourceExtension) {
            return sourceExtension
        }

        return "mov"
    }

    private func selectedVideoStreamsContain(codec: String) -> Bool {
        mediaInfo?.videoStreams.contains {
            project.selectedStreams.contains($0.index)
                && $0.codecName?.lowercased() == codec.lowercased()
        } ?? false
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.isPlaying = self.player.timeControlStatus == .playing
            }
        }
    }

    private func handleExportEvent(_ event: ExportEvent) {
        switch event {
        case .preparing:
            exportEvents.append("Preparing export")
        case let .processingSegment(current, total):
            exportEvents.append("Exporting segment \(current) of \(total)")
        case .concatenating:
            exportEvents.append("Merging segments")
        case let .progress(fraction, _):
            exportEvents.append("Progress \(Int(fraction * 100))%")
        case let .completed(url):
            exportEvents.append("Wrote \(url.lastPathComponent)")
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = errorMessage ?? "Something went wrong"
    }

    var cropPreviewRectangle: CropRectangle? {
        try? project.exportPreset.crop.rectangle(
            sourceWidth: mediaInfo?.videoStreams.first?.width,
            sourceHeight: mediaInfo?.videoStreams.first?.height
        )
    }

    func setCropToFullFrame() {
        guard let video = mediaInfo?.videoStreams.first,
              let width = video.width,
              let height = video.height else { return }
        project.exportPreset.crop.x = 0
        project.exportPreset.crop.y = 0
        project.exportPreset.crop.width = width
        project.exportPreset.crop.height = height
        project.modifiedAt = Date()
    }

    func setCropRectangle(_ rectangle: CropRectangle) {
        project.exportPreset.crop.isEnabled = true
        project.exportPreset.crop.x = rectangle.x
        project.exportPreset.crop.y = rectangle.y
        project.exportPreset.crop.width = rectangle.width
        project.exportPreset.crop.height = rectangle.height
        project.modifiedAt = Date()
    }

    func setCenteredCrop(aspectWidth: Int, aspectHeight: Int) {
        guard let video = mediaInfo?.videoStreams.first,
              let sourceWidth = video.width,
              let sourceHeight = video.height else { return }
        let targetRatio = Double(aspectWidth) / Double(aspectHeight)
        let sourceRatio = Double(sourceWidth) / Double(sourceHeight)

        let cropWidth: Int
        let cropHeight: Int
        if sourceRatio > targetRatio {
            cropHeight = sourceHeight
            cropWidth = Int(Double(sourceHeight) * targetRatio)
        } else {
            cropWidth = sourceWidth
            cropHeight = Int(Double(sourceWidth) / targetRatio)
        }

        project.exportPreset.crop.x = max(0, (sourceWidth - cropWidth) / 2)
        project.exportPreset.crop.y = max(0, (sourceHeight - cropHeight) / 2)
        project.exportPreset.crop.width = cropWidth
        project.exportPreset.crop.height = cropHeight
        project.modifiedAt = Date()
    }

    func diagnostics(for segment: Segment) -> SegmentKeyframeDiagnostics? {
        guard let before = keyframeIndex.nearestBefore(segment.sourceStart) else { return nil }
        let after = keyframeIndex.nearestAfter(segment.sourceStart)
        return SegmentKeyframeDiagnostics(
            requestedStart: segment.sourceStart,
            previousKeyframe: before,
            nextKeyframe: after,
            offsetFromPrevious: segment.sourceStart - before
        )
    }
}

struct SegmentKeyframeDiagnostics: Sendable {
    var requestedStart: Double
    var previousKeyframe: Double
    var nextKeyframe: Double?
    var offsetFromPrevious: Double
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case segments = "Segments"
    case media = "Media"
    case export = "Export"

    var id: String { rawValue }
}
