import SwiftUI

struct TimelinePane: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Timeline", systemImage: "timeline.selection")
                    .font(.headline)

                Spacer()

                if let inPoint = store.inPoint {
                    Text("In \(TimecodeFormatter.string(from: inPoint))")
                }
                if let outPoint = store.outPoint {
                    Text("Out \(TimecodeFormatter.string(from: outPoint))")
                }

                Divider()
                    .frame(height: 16)

                Button {
                    store.zoomTimeline(by: 1.6)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help("Zoom in")

                Button {
                    store.zoomTimeline(by: 1 / 1.6)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help("Zoom out")

                Button {
                    store.fitTimeline()
                } label: {
                    Label("Fit", systemImage: "arrow.left.and.right")
                }
                .labelStyle(.iconOnly)
                .help("Fit timeline")

                Text("\(Int(store.timelineZoom.rounded()))x")
                    .font(.system(.caption, design: .monospaced))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.bar)

            TimelineViewRepresentable(
                duration: max(store.duration, 1),
                visibleStart: store.timelineVisibleStart,
                visibleDuration: store.timelineVisibleDuration,
                currentTime: store.currentTime,
                inPoint: store.inPoint,
                outPoint: store.outPoint,
                segments: store.project.segments,
                selectedSegmentID: store.selectedSegmentID,
                keyframes: store.keyframeIndex.timestamps,
                thumbnails: store.thumbnails,
                waveform: store.waveform,
                onSeek: { store.seek(to: $0) },
                onSelect: { store.selectedSegmentID = $0 },
                onResizeSegment: { id, start, end in
                    store.updateSegment(id: id, start: start, end: end)
                },
                onMoveSegment: { id, index in
                    store.moveSegment(id: id, to: index)
                },
                onPanTimeline: { fraction in
                    store.panTimeline(by: fraction)
                }
            )
            .frame(minHeight: 130)
        }
    }
}
