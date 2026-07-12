import SwiftUI

struct MediaInspector: View {
    @Bindable var store: EditorStore
    @State private var isMetadataExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let mediaInfo = store.mediaInfo {
                MediaSummary(mediaInfo: mediaInfo)

                GroupBox("File") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        InfoRow(
                            "Location",
                            (mediaInfo.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                        )
                        InfoRow("Format", displayFormat(mediaInfo.formatName))
                        InfoRow("Duration", TimecodeFormatter.string(from: mediaInfo.duration ?? 0))
                        if let size = mediaInfo.size {
                            InfoRow("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        }
                        if let bitRate = mediaInfo.bitRate {
                            InfoRow("Bit rate", formattedBitRate(bitRate))
                        }
                        if let creationDate = mediaInfo.creationDateText {
                            InfoRow("Created", creationDate)
                        }
                        if let camera = mediaInfo.cameraText {
                            InfoRow("Camera", camera)
                        }
                        if let location = mediaInfo.locationText {
                            InfoRow("GPS", location)
                        }
                    }
                    .padding(.vertical, 4)
                }

                InfoSection("Preview") {
                    HStack(spacing: 8) {
                        Label(store.isUsingProxy ? "Proxy" : "Original", systemImage: store.isUsingProxy ? "film.stack" : "film")
                            .font(.callout.weight(.medium))
                        Spacer()
                        if store.isBuildingProxy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let proxyURL = store.proxyURL, store.isUsingProxy {
                        Text(proxyURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(proxyURL.path)
                    }

                    HStack(spacing: 8) {
                        Button {
                            store.buildAndUseProxy()
                        } label: {
                            Label(store.proxyURL == nil ? "Create Proxy" : "Rebuild", systemImage: "film.stack")
                        }
                        .disabled(store.isBuildingProxy)

                        Button {
                            store.useOriginalPreview()
                        } label: {
                            Label("Original", systemImage: "film")
                        }
                        .disabled(!store.isUsingProxy)
                    }
                    .controlSize(.small)
                }

                InfoSection("Streams", detail: "\(mediaInfo.streams.count)") {
                    VStack(spacing: 6) {
                        ForEach(mediaInfo.streams) { stream in
                            StreamSelectionRow(
                                stream: stream,
                                isSelected: Binding(
                                    get: { store.project.selectedStreams.contains(stream.index) },
                                    set: { enabled in
                                        if enabled {
                                            store.project.selectedStreams.insert(stream.index)
                                        } else {
                                            store.project.selectedStreams.remove(stream.index)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }

                DisclosureGroup(isExpanded: $isMetadataExpanded) {
                    MetadataEditor(mediaInfo: mediaInfo, store: store)
                        .padding(.top, 10)
                } label: {
                    HStack {
                        Text("Metadata")
                            .font(.headline)
                        Spacer()
                        if !store.project.exportPreset.metadataOverrides.isEmpty {
                            Text("\(store.project.exportPreset.metadataOverrides.count) edited")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        } else {
                            Text("\(mediaInfo.allMetadata.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !mediaInfo.chapters.isEmpty {
                    InfoSection("Chapters", detail: "\(mediaInfo.chapters.count)") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            ForEach(mediaInfo.chapters) { chapter in
                                InfoRow(chapter.title ?? "Chapter \(chapter.index)", TimecodeFormatter.string(from: chapter.start))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Media", systemImage: "film")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(16)
    }

    private func displayFormat(_ format: String?) -> String {
        guard let format else { return "Unknown" }
        if format.lowercased().contains("mp4") { return "MPEG-4" }
        if format.lowercased().contains("matroska") { return "Matroska" }
        return format
    }

    private func formattedBitRate(_ bitRate: Int64) -> String {
        let megabitsPerSecond = Double(bitRate) / 1_000_000
        return String(format: "%.1f Mb/s", megabitsPerSecond)
    }
}

private struct MediaSummary: View {
    let mediaInfo: MediaInfo

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(mediaInfo.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .help(mediaInfo.url.path)
    }

    private var summaryText: String {
        let video = mediaInfo.videoStreams.first
        let resolution = if let width = video?.width, let height = video?.height {
            "\(width) x \(height)"
        } else {
            "No video"
        }
        let codec = video?.codecName?.uppercased() ?? ""
        return [codec, resolution].filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

private struct StreamSelectionRow: View {
    let stream: MediaStream
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryText)
                        .lineLimit(1)
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch stream.kind {
        case .video: "video"
        case .audio: "waveform"
        case .subtitle: "captions.bubble"
        default: "doc"
        }
    }

    private var primaryText: String {
        "#\(stream.index) \(stream.kind.rawValue.capitalized)"
    }

    private var secondaryText: String {
        var details = [stream.codecName?.uppercased()]
        if let width = stream.width, let height = stream.height {
            details.append("\(width) x \(height)")
        }
        if let channels = stream.channels {
            details.append("\(channels) ch")
        }
        if let language = stream.language, language != "und" {
            details.append(language.uppercased())
        }
        return details.compactMap { $0 }.joined(separator: "  ·  ")
    }
}

private struct MetadataEditor: View {
    let mediaInfo: MediaInfo
    @Bindable var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Values are inherited on export. Enter a value only when you want to override the original.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if mediaInfo.allMetadata.isEmpty {
                Text("No metadata reported")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mediaInfo.allMetadata.keys.sorted(), id: \.self) { key in
                    MetadataEditorRow(
                        key: key,
                        originalValue: mediaInfo.allMetadata[key] ?? "",
                        override: metadataBinding(for: key)
                    )
                }
            }

            ForEach(mediaInfo.streams.filter { !$0.metadata.isEmpty }) { stream in
                DisclosureGroup(stream.displayName) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(stream.metadata.keys.sorted(), id: \.self) { key in
                            InfoRow(key, stream.metadata[key] ?? "")
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func metadataBinding(for key: String) -> Binding<String> {
        Binding(
            get: { store.project.exportPreset.metadataOverrides[key] ?? "" },
            set: { value in
                if value.isEmpty {
                    store.project.exportPreset.metadataOverrides.removeValue(forKey: key)
                } else {
                    store.project.exportPreset.metadataOverrides[key] = value
                }
            }
        )
    }
}

private struct MetadataEditorRow: View {
    let key: String
    let originalValue: String
    @Binding var override: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key)
                    .font(.caption)
                    .foregroundStyle(override.isEmpty ? Color.secondary : Color.accentColor)
                    .lineLimit(1)
                Spacer()
                if !override.isEmpty {
                    Text("Edited")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            if override.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(originalValue)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button("Override") {
                        override = originalValue
                    }
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 6) {
                    TextField("Override", text: $override)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        override = ""
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Restore original value")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct InfoSection<Content: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
    }
}
