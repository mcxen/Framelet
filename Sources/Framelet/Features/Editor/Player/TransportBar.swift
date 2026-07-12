import SwiftUI

struct TransportBar: View {
    @Bindable var store: EditorStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    PlaybackControls(store: store)
                    Spacer(minLength: 16)
                    TimeReadout(store: store)
                    Spacer(minLength: 16)
                    MarkingControls(store: store)
                }

                Scrubber(store: store)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    PlaybackControls(store: store)
                    Spacer()
                    TimeReadout(store: store)
                }

                Scrubber(store: store)

                HStack(spacing: 8) {
                    Spacer()
                    MarkingControls(store: store)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct PlaybackControls: View {
    @Bindable var store: EditorStore

    var body: some View {
        HStack(spacing: 6) {
            Button {
                store.jumpToPreviousKeyframe()
            } label: {
                Label("Previous Keyframe", systemImage: "backward.end")
            }
            .labelStyle(.iconOnly)
            .disabled(store.keyframeIndex.timestamps.isEmpty)

            Button {
                store.step(by: -1)
            } label: {
                Label("Back 1s", systemImage: "gobackward.1")
            }
            .labelStyle(.iconOnly)

            Button {
                store.stepFrame(direction: -1)
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
                store.stepFrame(direction: 1)
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

            Button {
                store.jumpToNextKeyframe()
            } label: {
                Label("Next Keyframe", systemImage: "forward.end")
            }
            .labelStyle(.iconOnly)
            .disabled(store.keyframeIndex.timestamps.isEmpty)
        }
        .buttonStyle(.bordered)
    }
}

private struct TimeReadout: View {
    let store: EditorStore

    var body: some View {
        Text("\(TimecodeFormatter.string(from: store.currentTime)) / \(TimecodeFormatter.string(from: store.duration))")
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 190)
    }
}

private struct MarkingControls: View {
    @Bindable var store: EditorStore

    var body: some View {
        HStack(spacing: 8) {
            Button("I") {
                store.setInPoint()
            }
            .help("Set in point")

            Button("O") {
                store.setOutPoint()
            }
            .help("Set out point")

            Button {
                store.toggleCropSelection()
            } label: {
                Label("Crop", systemImage: "crop")
            }
            .buttonStyle(.bordered)
            .tint(store.isCropSelectionActive ? .accentColor : nil)
            .quickHelp("Select a crop area on the video")
            .disabled(store.mediaInfo?.videoStreams.isEmpty != false)

            Button {
                store.createSegmentFromMarks()
            } label: {
                Label("Split", systemImage: "scissors")
            }
            .disabled(!store.canCreateSegmentFromMarks)
            .quickHelp("Create a segment between the In and Out points")

            Button(role: .destructive) {
                store.deleteSelectedSegment()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(store.selectedSegmentID == nil)
        }
    }
}

private struct Scrubber: View {
    @Bindable var store: EditorStore
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        Slider(
            value: Binding(
                get: { isScrubbing ? scrubTime : store.currentTime },
                set: { value in
                    scrubTime = value
                    store.previewSeek(to: value)
                }
            ),
            in: 0...max(store.duration, 0.001),
            onEditingChanged: { editing in
                if editing {
                    scrubTime = store.currentTime
                    isScrubbing = true
                } else {
                    isScrubbing = false
                    store.finishPreviewSeek(at: scrubTime)
                }
            }
        )
    }
}
