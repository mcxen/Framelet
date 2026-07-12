import SwiftUI

struct ExportInspector: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ExportSummaryCard(store: store)

            GroupBox("Output") {
                VStack(alignment: .leading, spacing: 12) {
            Picker("Output", selection: $store.project.exportPreset.mode) {
                Text("Separate files").tag(ExportMode.separateFiles)
                Text("Merged file").tag(ExportMode.mergedFile)
            }
            .pickerStyle(.radioGroup)

            Picker("Container", selection: $store.project.exportPreset.containerExtension) {
                Text("MOV").tag("mov")
                Text("MP4").tag("mp4")
                Text("MKV").tag("mkv")
                Text("M4A").tag("m4a")
            }

            if store.mediaInfo?.videoStreams.contains(where: { $0.codecName?.lowercased() == "av1" }) == true,
               store.project.exportPreset.containerExtension == "mov",
               !store.project.exportPreset.crop.isEnabled {
                Text("AV1 stream-copy export uses MP4; MOV cannot store AV1 video.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            TextField("Naming pattern", text: $store.project.exportPreset.namingPattern)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Picture") {
                CropExportControls(store: store)
                    .padding(.vertical, 4)
            }

            if store.isExporting {
                ExportProgressView(
                    progress: store.exportProgress,
                    phase: store.exportPhase,
                    currentSegment: store.exportCurrentSegment,
                    totalSegments: store.exportSegmentCount,
                    speed: store.exportSpeed,
                    estimatedRemaining: store.exportEstimatedRemaining
                )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }

            VStack(spacing: 10) {
            Button {
                store.quickExportBesideOriginal()
            } label: {
                Label("Quick Export Beside Original", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.project.segments.filter(\.isEnabled).isEmpty || store.isExporting)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Button {
                store.exportSeparateSegments()
            } label: {
                Label("Export to Folder…", systemImage: "square.and.arrow.up")
            }
            .disabled(store.project.segments.filter(\.isEnabled).isEmpty || store.isExporting)
            .frame(maxWidth: .infinity)
            }

            if store.project.exportPreset.mode == .mergedFile {
                Text("Merged export writes temporary segment files first, then concatenates them into one output file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !store.exportEvents.isEmpty {
                Divider()
                InfoSection("Recent Export") {
                    ForEach(Array(store.exportEvents.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            CommandLogView(store: store)
        }
        .padding(16)
        .onAppear {
            store.refreshCommandLog()
        }
    }
}

private struct ExportProgressView: View {
    let progress: Double
    let phase: ExportPhase
    let currentSegment: Int
    let totalSegments: Int
    let speed: Double?
    let estimatedRemaining: TimeInterval?

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var percentage: Int {
        Int((clampedProgress * 100).rounded())
    }

    private var detail: String? {
        if phase == .exporting, currentSegment > 0, totalSegments > 0 {
            return "Segment \(currentSegment) of \(totalSegments)"
        }
        if phase == .merging {
            return "Writing the final file"
        }
        return nil
    }

    private var metrics: String? {
        var values: [String] = []
        if let speed, speed.isFinite, speed > 0 {
            values.append(String(format: "%.1f×", speed))
        }
        if phase == .exporting, let estimatedRemaining, estimatedRemaining.isFinite {
            let duration = Duration.seconds(estimatedRemaining)
            values.append("About \(duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))) left")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(phase.displayName)
                    .font(.headline)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .contentTransition(.numericText())
            }

            ProgressView(value: clampedProgress)
                .progressViewStyle(.linear)

            HStack {
                if let detail {
                    Text(detail)
                }
                Spacer()
                if let metrics {
                    Text(metrics)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Export progress")
        .accessibilityValue("\(phase.displayName), \(percentage)%")
    }
}

private struct ExportSummaryCard: View {
    @Bindable var store: EditorStore

    private var enabledSegments: [Segment] { store.project.segments.filter(\.isEnabled) }
    private var duration: Double { enabledSegments.reduce(0) { $0 + $1.duration } }
    private var dimensions: String {
        if let crop = store.cropPreviewRectangle, store.project.exportPreset.crop.isEnabled {
            return "\(crop.width) × \(crop.height)"
        }
        guard let video = store.mediaInfo?.videoStreams.first,
              let width = video.width, let height = video.height else { return "—" }
        return "\(width) × \(height)"
    }

    var body: some View {
        HStack(spacing: 0) {
            summaryItem(icon: "scissors", value: "\(enabledSegments.count)", label: "Segments")
            Divider().frame(height: 38)
            summaryItem(icon: "clock", value: TimecodeFormatter.string(from: duration), label: "Duration")
            Divider().frame(height: 38)
            summaryItem(icon: "rectangle.inset.filled", value: dimensions, label: "Picture")
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryItem(icon: String, value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Label(value, systemImage: icon).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CommandLogView: View {
    @Bindable var store: EditorStore

    var body: some View {
        InfoSection("Last FFmpeg Commands") {
            if store.commandLogEntries.isEmpty {
                Text("Commands will appear after media analysis, proxy generation, waveform building, or export.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button {
                        store.refreshCommandLog()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        store.clearCommandLog()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
                .buttonStyle(.bordered)

                ForEach(store.commandLogEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.copyCommandToClipboard(entry.command)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .labelStyle(.iconOnly)
                            .help("Copy command")
                        }

                        Text(entry.command)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(4)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}

private struct CropExportControls: View {
    @Bindable var store: EditorStore

    private var sourceWidth: Int {
        store.mediaInfo?.videoStreams.first?.width ?? 3840
    }

    private var sourceHeight: Int {
        store.mediaInfo?.videoStreams.first?.height ?? 2160
    }

    private var crop: CropRectangle {
        store.cropPreviewRectangle ?? CropRectangle(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
    }

    private func binding(for keyPath: WritableKeyPath<CropRectangle, Int>) -> Binding<Int> {
        Binding(
            get: { crop[keyPath: keyPath] },
            set: { value in
                var updated = crop
                updated[keyPath: keyPath] = value
                store.setCropRectangle(updated)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Crop picture",
                isOn: Binding(
                    get: { store.project.exportPreset.crop.isEnabled },
                    set: { isEnabled in
                        store.setCropEnabled(isEnabled)
                    }
                )
            )

            if store.project.exportPreset.crop.isEnabled {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        CropStepper(
                            title: "X",
                            value: binding(for: \.x),
                            range: 0...max(0, sourceWidth - 2)
                        )
                        CropStepper(
                            title: "Y",
                            value: binding(for: \.y),
                            range: 0...max(0, sourceHeight - 2)
                        )
                    }

                    GridRow {
                        CropStepper(
                            title: "Width",
                            value: binding(for: \.width),
                            range: 2...max(2, sourceWidth - crop.x)
                        )
                        CropStepper(
                            title: "Height",
                            value: binding(for: \.height),
                            range: 2...max(2, sourceHeight - crop.y)
                        )
                    }
                }

                Text("Drag the frame handles to resize, or drag inside the frame to reposition it. Values are kept inside the source image.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Full") {
                        store.setCropToFullFrame()
                    }
                    Button("1:1") {
                        store.setCenteredCrop(aspectWidth: 1, aspectHeight: 1)
                    }
                    Button("16:9") {
                        store.setCenteredCrop(aspectWidth: 16, aspectHeight: 9)
                    }
                    Button("4:3") {
                        store.setCenteredCrop(aspectWidth: 4, aspectHeight: 3)
                    }
                    Button("9:16") {
                        store.setCenteredCrop(aspectWidth: 9, aspectHeight: 16)
                    }
                    Button("3:4") {
                        store.setCenteredCrop(aspectWidth: 3, aspectHeight: 4)
                    }
                }
                .buttonStyle(.bordered)

                Picker("Video codec", selection: $store.project.exportPreset.videoEncode.codec) {
                    ForEach(VideoCodec.allCases, id: \.self) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }

                Stepper(
                    value: $store.project.exportPreset.videoEncode.bitrateMbps,
                    in: 2...80
                ) {
                    HStack {
                        Text("Bitrate")
                        Spacer()
                        Text("\(store.project.exportPreset.videoEncode.bitrateMbps) Mbps")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .disabled(store.project.exportPreset.videoEncode.codec != .h264VideoToolbox)

                Text("Cropping changes picture pixels, so Framelet re-encodes video while copying other selected streams when possible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CropStepper: View {
    var title: LocalizedStringKey
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range, step: 2) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
    }
}
