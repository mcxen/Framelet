import AppKit
import SwiftUI

struct EditorView: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VSplitView {
                    PlayerPane(store: store)
                        .frame(minHeight: 280, idealHeight: 520)

                    TimelinePane(store: store)
                        .frame(minHeight: 190, idealHeight: 260)
                }
                .frame(minWidth: 640)

                if store.showInspector {
                    InspectorView(store: store)
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                }
            }
            .overlay {
                if store.mediaInfo == nil && !store.isLoading {
                    EmptyProjectPrompt {
                        store.chooseAndOpenMedia()
                    }
                    .padding(.bottom, 60)
                }
            }

            StatusBar(store: store)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    store.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .labelStyle(.titleAndIcon)
                .quickHelp("Show or hide Media, Segments, and Export settings")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.exportSeparateSegments()
                } label: {
                    Label("Export", systemImage: "film.stack")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .disabled(store.mediaInfo == nil || store.isExporting)
                .quickHelp("Export enabled video segments")
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
        .background(EditorKeyboardShortcuts(store: store))
        .alert("Framelet", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct EditorKeyboardShortcuts: NSViewRepresentable {
    let store: EditorStore

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install(store: store)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.store = store
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var store: EditorStore?
        private var monitor: Any?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        @MainActor
        func install(store: EditorStore) {
            self.store = store
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handle(event) else { return event }
                return nil
            }
        }

        @MainActor
        private func handle(_ event: NSEvent) -> Bool {
            guard let store, store.mediaInfo != nil, !isTextInputActive else { return false }

            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isShiftOnly = modifierFlags == .shift
            let hasUnsupportedModifiers = !modifierFlags.subtracting(.shift).isEmpty
            guard !hasUnsupportedModifiers else { return false }

            switch event.keyCode {
            case 123:
                isShiftOnly ? store.step(by: -1) : store.stepFrame(direction: -1)
                return true
            case 124:
                isShiftOnly ? store.step(by: 1) : store.stepFrame(direction: 1)
                return true
            default:
                return false
            }
        }

        @MainActor
        private var isTextInputActive: Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            if responder is NSTextView {
                return true
            }
            if let view = responder as? NSView,
               sequence(first: view, next: { $0.superview }).contains(where: { $0 is NSTextField }) {
                return true
            }
            return false
        }
    }
}

private struct EmptyProjectPrompt: View {
    var openMedia: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Drop media here")
                    .font(.title3.weight(.semibold))
                Text("Open a video or audio file to start trimming.")
                    .foregroundStyle(.secondary)
            }

            Button {
                openMedia()
            } label: {
                Label("Open Media", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusBar: View {
    let store: EditorStore

    var body: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(store.statusMessage))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let mediaInfo = store.mediaInfo {
                        StatusMetric(summary(for: mediaInfo))
                        if store.isLoadingKeyframes {
                            StatusMetric("Scanning keyframes")
                        } else if !store.keyframeIndex.timestamps.isEmpty {
                            StatusMetric("\(store.keyframeIndex.timestamps.count)", unit: "keyframes")
                        }
                        if store.isLoadingThumbnails {
                            StatusMetric("Building thumbnails")
                        } else if !store.thumbnails.isEmpty {
                            StatusMetric("\(store.thumbnails.count)", unit: "thumbnails")
                        }
                        if store.isLoadingWaveform {
                            StatusMetric("Building waveform")
                        } else if !store.waveform.samples.isEmpty {
                            StatusMetric("\(store.waveform.samples.count)", unit: "waveform peaks")
                        }
                        if store.isBuildingProxy {
                            StatusMetric("Building proxy")
                        } else if store.isUsingProxy {
                            StatusMetric("Proxy preview")
                        }
                    }

                    StatusMetric("\(store.project.segments.count)", unit: "segments")
                    StatusMetric(TimecodeFormatter.string(from: store.enabledSegmentsDuration))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 560, alignment: .trailing)
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

private struct StatusMetric: View {
    var value: String
    var unit: LocalizedStringKey?

    init(_ value: String) {
        self.value = value
        unit = nil
    }

    init(_ value: String, unit: LocalizedStringKey) {
        self.value = value
        self.unit = unit
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(LocalizedStringKey(value))
            if let unit {
                Text(unit)
            }
        }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
