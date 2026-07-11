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
                        TimeField(value: segment.sourceStart) { value in
                            store.updateSelectedSegment { $0.sourceStart = max(0, min(value, $0.sourceEnd)) }
                        }
                    }
                    GridRow {
                        Text("End")
                            .foregroundStyle(.secondary)
                        TimeField(value: segment.sourceEnd) { value in
                            store.updateSelectedSegment { $0.sourceEnd = max($0.sourceStart, value) }
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
                        Text(color.rawValue.capitalized).tag(color)
                    }
                }

                Divider()

                Button {
                    store.seek(to: segment.sourceStart)
                } label: {
                    Label("Go to Start", systemImage: "arrow.left.to.line")
                }

                Button {
                    store.seek(to: segment.sourceEnd)
                } label: {
                    Label("Go to End", systemImage: "arrow.right.to.line")
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
            } else {
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
        .padding(16)
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
