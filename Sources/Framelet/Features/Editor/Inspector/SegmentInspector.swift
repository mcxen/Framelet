import SwiftUI

struct SegmentInspector: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button {
                    store.importSegmentsFromCSV()
                } label: {
                    Label("Import CSV", systemImage: "tray.and.arrow.down")
                }

                Button {
                    store.exportSegmentsToCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(store.project.segments.isEmpty)
            }
            .buttonStyle(.bordered)

            if !store.project.segments.isEmpty {
                SegmentList(store: store)
            }

            if let segment = store.selectedSegment {
                TextField(
                    "Name",
                    text: Binding(
                        get: { segment.name },
                        set: { newValue in
                            store.updateSelectedSegment { $0.name = newValue }
                        }
                    )
                )

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Start")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            TimeField(value: segment.sourceStart) { value in
                                store.setSelectedSegmentBoundary(.start, to: value)
                            }
                            SegmentBoundaryControls(store: store, boundary: .start)
                        }
                    }
                    GridRow {
                        Text("End")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            TimeField(value: segment.sourceEnd) { value in
                                store.setSelectedSegmentBoundary(.end, to: value)
                            }
                            SegmentBoundaryControls(store: store, boundary: .end)
                        }
                    }
                    GridRow {
                        Text("Duration")
                            .foregroundStyle(.secondary)
                        Text(TimecodeFormatter.string(from: segment.duration))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { segment.isEnabled },
                        set: { enabled in store.updateSelectedSegment { $0.isEnabled = enabled } }
                    )
                )

                HStack(spacing: 10) {
                    Button {
                        store.toggleSelectedSegmentPreview()
                    } label: {
                        Label(
                            store.previewingSegmentID == segment.id && store.isPlaying
                                ? "Pause Preview"
                                : "Preview Segment",
                            systemImage: store.previewingSegmentID == segment.id && store.isPlaying
                                ? "pause.fill"
                                : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.mediaInfo == nil)

                    ProgressView(value: store.segmentPreviewProgress(for: segment), total: 1)
                        .progressViewStyle(.linear)
                        .help("Segment preview progress")
                }

                if let diagnostics = store.selectedSegmentKeyframeDiagnostics {
                    InfoSection("Keyframe") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                            InfoRow("Requested", TimecodeFormatter.string(from: diagnostics.requestedStart))
                            InfoRow("Previous", TimecodeFormatter.string(from: diagnostics.previousKeyframe))
                            InfoRow("Offset", String(format: "%.0f ms", diagnostics.offsetFromPrevious * 1000))
                            if let next = diagnostics.nextKeyframe {
                                InfoRow("Next", TimecodeFormatter.string(from: next))
                            }
                        }
                    }
                } else if !store.keyframeIndex.timestamps.isEmpty {
                    Text("No previous keyframe found for this segment start.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker(
                    "Color",
                    selection: Binding(
                        get: { segment.colorTag ?? .blue },
                        set: { color in store.updateSelectedSegment { $0.colorTag = color } }
                    )
                ) {
                    ForEach(SegmentColor.allCases, id: \.self) { color in
                        Text(LocalizedStringKey(color.rawValue.capitalized)).tag(color)
                    }
                }

                Button(role: .destructive) {
                    store.deleteSelectedSegment()
                } label: {
                    Label("Delete Segment", systemImage: "trash")
                }
            } else if store.project.segments.isEmpty {
                ContentUnavailableView(
                    "No Segment Selected",
                    systemImage: "timeline.selection",
                    description: Text("Set in and out points, then create a segment.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(16)
    }
}

private struct SegmentList: View {
    @Bindable var store: EditorStore

    var body: some View {
        InfoSection("Segments") {
            ForEach(store.project.segments) { segment in
                Button {
                    store.selectedSegmentID = segment.id
                    store.seek(to: segment.sourceStart)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.name)
                                .font(.body)
                            Text("\(TimecodeFormatter.string(from: segment.sourceStart)) – \(TimecodeFormatter.string(from: segment.sourceEnd))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if segment.id == store.selectedSegmentID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SegmentBoundaryControls: View {
    @Bindable var store: EditorStore
    var boundary: SegmentBoundary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    store.seekSelectedSegmentBoundary(boundary)
                } label: {
                    Label(boundary == .start ? "Go to Start" : "Go to End", systemImage: "playhead.arrowtriangle.right")
                }
                .help(boundary == .start ? "Move the playhead to this segment start" : "Move the playhead to this segment end")

                Button {
                    store.setSelectedSegmentBoundaryToCurrentTime(boundary)
                } label: {
                    Label("Use Playhead", systemImage: "scope")
                }
                .help(boundary == .start ? "Set segment start to the current playhead" : "Set segment end to the current playhead")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text("Fine adjustment")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button {
                    store.nudgeSelectedSegmentBoundary(boundary, by: -store.frameStepDuration)
                } label: {
                    Label("Previous Frame", systemImage: "backward.frame")
                }
                .help("Move this boundary back one frame")

                Button {
                    store.nudgeSelectedSegmentBoundary(boundary, by: store.frameStepDuration)
                } label: {
                    Label("Next Frame", systemImage: "forward.frame")
                }
                .help("Move this boundary forward one frame")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 6) {
                Button {
                    store.moveSelectedSegmentBoundaryToAdjacentKeyframe(boundary, direction: -1)
                } label: {
                    Label("Previous Keyframe", systemImage: "backward.end")
                }
                .help("Move this boundary to the previous keyframe")
                .disabled(store.keyframeIndex.timestamps.isEmpty)

                Button {
                    store.moveSelectedSegmentBoundaryToAdjacentKeyframe(boundary, direction: 1)
                } label: {
                    Label("Next Keyframe", systemImage: "forward.end")
                }
                .help("Move this boundary to the next keyframe")
                .disabled(store.keyframeIndex.timestamps.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct TimeField: View {
    var value: Double
    var onCommit: (Double) -> Void
    @State private var text = ""

    var body: some View {
        TextField("Seconds", text: $text)
            .font(.system(.body, design: .monospaced))
            .onAppear {
                text = String(format: "%.3f", value)
            }
            .onChange(of: value) { _, newValue in
                text = String(format: "%.3f", newValue)
            }
            .onSubmit {
                if let value = Double(text) {
                    onCommit(value)
                }
            }
    }
}
