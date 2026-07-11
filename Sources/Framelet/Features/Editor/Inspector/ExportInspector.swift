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
                ExportProgressView(progress: store.exportProgress)
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

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var percentage: Int {
        Int((clampedProgress * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(percentage)%")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
            }
            .frame(width: 60, height: 60)

            Text("Exporting")
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Export progress")
        .accessibilityValue("\(percentage)%")
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
                            value: $store.project.exportPreset.crop.x,
                            range: 0...max(0, sourceWidth - 2)
                        )
                        CropStepper(
                            title: "Y",
                            value: $store.project.exportPreset.crop.y,
                            range: 0...max(0, sourceHeight - 2)
                        )
                    }

                    GridRow {
                        CropOptionalStepper(
                            title: "Width",
                            value: $store.project.exportPreset.crop.width,
                            fallback: sourceWidth,
                            range: 2...sourceWidth
                        )
                        CropOptionalStepper(
                            title: "Height",
                            value: $store.project.exportPreset.crop.height,
                            fallback: sourceHeight,
                            range: 2...sourceHeight
                        )
                    }
                }

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
                    Button("9:16") {
                        store.setCenteredCrop(aspectWidth: 9, aspectHeight: 16)
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
        Stepper(value: $value, in: range) {
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

private struct CropOptionalStepper: View {
    var title: LocalizedStringKey
    @Binding var value: Int?
    var fallback: Int
    var range: ClosedRange<Int>

    var body: some View {
        Stepper(
            value: Binding(
                get: { value ?? fallback },
                set: { value = $0 }
            ),
            in: range
        ) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Text("\(value ?? fallback)")
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
    }
}
