import SwiftUI

struct EditorView: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 0) {
                    PlayerPane(store: store)
                    TimelinePane(store: store)
                }
                .frame(minWidth: 720)

                if store.showInspector {
                    InspectorView(store: store)
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
                }
            }

            StatusBar(store: store)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.chooseAndOpenMedia()
                } label: {
                    Label("Open", systemImage: "folder")
                }

                Button {
                    store.saveProject(to: store.projectURL)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }

                Button {
                    store.saveProject(to: nil)
                } label: {
                    Label("Save As", systemImage: "square.and.arrow.down.on.square")
                }

                Button {
                    store.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }

                Button {
                    store.exportSeparateSegments()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(store.project.name)
        .dropDestination(for: URL.self) { urls, _ in
            store.openDroppedItems(urls)
        } isTargeted: { isTargeted in
            if isTargeted {
                store.statusMessage = "Drop to open and start trimming"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .frameletOpenMedia)) { _ in store.chooseAndOpenMedia() }
        .onReceive(NotificationCenter.default.publisher(for: .frameletOpenProject)) { _ in store.chooseAndOpenProject() }
        .onReceive(NotificationCenter.default.publisher(for: .frameletSaveProject)) { _ in store.saveProject(to: store.projectURL) }
        .onReceive(NotificationCenter.default.publisher(for: .frameletSaveProjectAs)) { _ in store.saveProject(to: nil) }
        .onReceive(NotificationCenter.default.publisher(for: .frameletSetInPoint)) { _ in store.setInPoint() }
        .onReceive(NotificationCenter.default.publisher(for: .frameletSetOutPoint)) { _ in store.setOutPoint() }
        .onReceive(NotificationCenter.default.publisher(for: .frameletCreateSegment)) { _ in store.createSegmentFromMarks() }
        .onReceive(NotificationCenter.default.publisher(for: .frameletImportSegmentsCSV)) { _ in store.importSegmentsFromCSV() }
        .onReceive(NotificationCenter.default.publisher(for: .frameletExportSegmentsCSV)) { _ in store.exportSegmentsToCSV() }
        .onReceive(NotificationCenter.default.publisher(for: .frameletExport)) { _ in store.exportSeparateSegments() }
        .alert("Framelet", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct StatusBar: View {
    let store: EditorStore

    var body: some View {
        HStack(spacing: 12) {
            Text(store.statusMessage)
                .lineLimit(1)

            Spacer()

            if let mediaInfo = store.mediaInfo {
                Text(summary(for: mediaInfo))
                if store.isLoadingKeyframes {
                    Text("Scanning keyframes")
                } else if !store.keyframeIndex.timestamps.isEmpty {
                    Text("\(store.keyframeIndex.timestamps.count) keyframes")
                }
                if store.isLoadingThumbnails {
                    Text("Building thumbnails")
                } else if !store.thumbnails.isEmpty {
                    Text("\(store.thumbnails.count) thumbnails")
                }
                if store.isLoadingWaveform {
                    Text("Building waveform")
                } else if !store.waveform.samples.isEmpty {
                    Text("\(store.waveform.samples.count) waveform peaks")
                }
                if store.isBuildingProxy {
                    Text("Building proxy")
                } else if store.isUsingProxy {
                    Text("Proxy preview")
                }
                Text("\(store.project.segments.count) segments")
                Text(TimecodeFormatter.string(from: store.enabledSegmentsDuration))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    private func summary(for mediaInfo: MediaInfo) -> String {
        let video = mediaInfo.videoStreams.first
        let codec = video?.codecName?.uppercased() ?? mediaInfo.formatName ?? "Media"
        if let width = video?.width, let height = video?.height {
            return "\(codec) · \(width)x\(height)"
        }
        return codec
    }
}
