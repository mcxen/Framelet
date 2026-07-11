import SwiftUI

struct MediaInspector: View {
    let store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let mediaInfo = store.mediaInfo {
                InfoSection("File") {
                    InfoRow("Path", mediaInfo.url.path)
                    InfoRow("Format", mediaInfo.formatName ?? "Unknown")
                    InfoRow("Duration", TimecodeFormatter.string(from: mediaInfo.duration ?? 0))
                    if let size = mediaInfo.size {
                        InfoRow("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }

                InfoSection("Preview") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        InfoRow("Mode", store.isUsingProxy ? "Proxy" : "Original")
                        if let proxyURL = store.proxyURL {
                            InfoRow("Proxy", proxyURL.path)
                        }
                    }

                    HStack {
                        Button {
                            store.buildAndUseProxy()
                        } label: {
                            Label("Create Proxy", systemImage: "film.stack")
                        }
                        .disabled(store.isBuildingProxy)

                        Button {
                            store.useOriginalPreview()
                        } label: {
                            Label("Use Original", systemImage: "film")
                        }
                        .disabled(!store.isUsingProxy)
                    }
                }

                InfoSection("Streams") {
                    ForEach(mediaInfo.streams) { stream in
                        Toggle(
                            stream.displayName,
                            isOn: Binding(
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

                if !mediaInfo.chapters.isEmpty {
                    InfoSection("Chapters") {
                        ForEach(mediaInfo.chapters) { chapter in
                            InfoRow(chapter.title ?? "Chapter \(chapter.index)", TimecodeFormatter.string(from: chapter.start))
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
}

struct InfoSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

struct InfoRow: View {
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}
