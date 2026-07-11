import SwiftUI

struct TransportBar: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    store.step(by: -1)
                } label: {
                    Label("Back 1s", systemImage: "gobackward.1")
                }
                .labelStyle(.iconOnly)

                Button {
                    store.step(by: -1 / 30)
                } label: {
                    Label("Previous Frame", systemImage: "backward.frame")
                }
                .labelStyle(.iconOnly)

                Button {
                    store.togglePlayback()
                } label: {
                    Label(store.isPlaying ? "Pause" : "Play", systemImage: store.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    store.step(by: 1 / 30)
                } label: {
                    Label("Next Frame", systemImage: "forward.frame")
                }
                .labelStyle(.iconOnly)

                Button {
                    store.step(by: 1)
                } label: {
                    Label("Forward 1s", systemImage: "goforward.1")
                }
                .labelStyle(.iconOnly)

                Spacer()

                Text("\(TimecodeFormatter.string(from: store.currentTime)) / \(TimecodeFormatter.string(from: store.duration))")
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Button("I") {
                    store.setInPoint()
                }
                .help("Set in point")

                Button("O") {
                    store.setOutPoint()
                }
                .help("Set out point")

                Button {
                    store.createSegmentFromMarks()
                } label: {
                    Label("Split", systemImage: "scissors")
                }

                Button(role: .destructive) {
                    store.deleteSelectedSegment()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(store.selectedSegmentID == nil)
            }

            Slider(
                value: Binding(
                    get: { store.currentTime },
                    set: { store.seek(to: $0) }
                ),
                in: 0...max(store.duration, 0.001)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
