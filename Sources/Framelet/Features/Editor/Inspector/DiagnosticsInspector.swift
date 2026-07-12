import SwiftUI

struct DiagnosticsInspector: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Media Processing Diagnostics", systemImage: "stethoscope")
                    .font(.headline)
                Text("Commands recorded while probing media, scanning keyframes, building waveforms or proxies, and exporting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
                .disabled(store.commandLogEntries.isEmpty)
            }
            .buttonStyle(.bordered)

            if store.commandLogEntries.isEmpty {
                ContentUnavailableView(
                    "No Diagnostic Commands",
                    systemImage: "terminal",
                    description: Text("Commands appear here after media processing or export.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(store.commandLogEntries) { entry in
                        DiagnosticCommandCard(store: store, entry: entry)
                    }
                }
            }
        }
        .padding(16)
        .onAppear {
            store.refreshCommandLog()
        }
    }
}

private struct DiagnosticCommandCard: View {
    let store: EditorStore
    let entry: CommandLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(commandKind, systemImage: commandIcon)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    store.copyCommandToClipboard(entry.command)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy command")
            }

            Text(entry.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private var commandKind: LocalizedStringKey {
        if entry.command.contains("ffprobe") { return "Media Probe" }
        if entry.command.contains("f32le") { return "Waveform" }
        if entry.command.contains("_proxy") { return "Proxy" }
        return "FFmpeg"
    }

    private var commandIcon: String {
        if entry.command.contains("ffprobe") { return "doc.text.magnifyingglass" }
        if entry.command.contains("f32le") { return "waveform" }
        if entry.command.contains("_proxy") { return "film.stack" }
        return "terminal"
    }
}
