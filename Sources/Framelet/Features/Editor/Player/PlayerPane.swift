import SwiftUI

struct PlayerPane: View {
    @Bindable var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                PlayerViewRepresentable(player: store.player)

                if let video = store.mediaInfo?.videoStreams.first,
                   let sourceWidth = video.width,
                   let sourceHeight = video.height {
                    CropOverlay(
                        sourceWidth: sourceWidth,
                        sourceHeight: sourceHeight,
                        crop: store.project.exportPreset.crop.isEnabled ? store.cropPreviewRectangle : nil,
                        allowsSelection: store.isCropSelectionActive,
                        onChange: store.setCropRectangle
                    )
                }

                if store.isCropSelectionActive, let crop = store.cropPreviewRectangle {
                    VStack {
                        CropEditingBar(store: store, crop: crop)
                            .padding(.top, 12)
                        Spacer()
                    }
                }

                if store.mediaInfo == nil {
                    ContentUnavailableView(
                        "No Media",
                        systemImage: "film",
                        description: Text("Open a file to start lossless trimming.")
                    )
                    .foregroundStyle(.secondary)
                }

                if store.isLoading || store.isPreparingPreview {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading video preview…")
                    }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                if let previewError = store.previewErrorMessage {
                    ContentUnavailableView(
                        "Preview Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(previewError)
                    )
                    .foregroundStyle(.secondary)
                }

                if store.isBuildingProxy {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Creating preview proxy")
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack {
                    HStack {
                        Spacer()
                        PreviewBadge(store: store)
                    }
                    Spacer()
                }
                .padding(12)
            }

            TransportBar(store: store)
        }
    }
}

private struct PreviewBadge: View {
    let store: EditorStore

    var body: some View {
        if store.mediaInfo != nil {
            Text(store.isUsingProxy ? "Proxy Preview" : "Original Preview")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(store.isUsingProxy ? .yellow : .secondary)
        }
    }
}

private struct CropEditingBar: View {
    @Bindable var store: EditorStore
    let crop: CropRectangle

    var body: some View {
        HStack(spacing: 8) {
            Label("\(crop.width) x \(crop.height)", systemImage: "crop")
                .font(.system(.callout, design: .monospaced, weight: .medium))
                .lineLimit(1)

            Divider()
                .frame(height: 18)

            Menu {
                Button("Original") {
                    store.setCropToFullFrame()
                }
                Button("1:1") {
                    store.setCenteredCrop(aspectWidth: 1, aspectHeight: 1)
                }
                Button("16:9") {
                    store.setCenteredCrop(aspectWidth: 16, aspectHeight: 9)
                }
                Button("9:16") {
                    store.setCenteredCrop(aspectWidth: 9, aspectHeight: 16)
                }
            } label: {
                Label("Aspect Ratio", systemImage: "aspectratio")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                store.setCropToFullFrame()
            } label: {
                Label("Reset Crop", systemImage: "arrow.counterclockwise")
            }
            .labelStyle(.iconOnly)
            .help("Reset Crop")

            Divider()
                .frame(height: 18)

            Button("Cancel", role: .cancel) {
                store.cancelCropSelection()
            }
            .keyboardShortcut(.cancelAction)

            Button("Done") {
                store.finishCropSelection()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .fixedSize()
    }
}

private struct CropOverlay: View {
    var sourceWidth: Int
    var sourceHeight: Int
    var crop: CropRectangle?
    var allowsSelection: Bool
    var onChange: (CropRectangle) -> Void

    @State private var dragStart: CropRectangle?
    @State private var selectionStart: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let videoFrame = fittedVideoFrame(in: geometry.size)
            let scale = cropScale(in: videoFrame)

            if allowsSelection, crop == nil {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .position(x: videoFrame.midX, y: videoFrame.midY)
                    // Drag locations are local to this hit plane, so map against a zero-origin
                    // video rectangle instead of the letterboxed position in the parent.
                    .gesture(selectionGesture(
                        videoFrame: CGRect(origin: .zero, size: videoFrame.size),
                        scale: scale
                    ))
            }

            if let crop {
                let cropFrame = cropFrame(for: crop, in: videoFrame)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(cropFrame)
                }
                .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                CropGrid()
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .allowsHitTesting(false)
                    .opacity(allowsSelection ? 1 : 0)

                Rectangle()
                    .fill(.clear)
                    .overlay {
                        Rectangle()
                            .stroke(.white, lineWidth: 3)
                            .shadow(color: .black.opacity(0.7), radius: 1)
                    }
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .contentShape(Rectangle())
                    .allowsHitTesting(allowsSelection)
                    .gesture(cropGesture(handle: .move, scale: scale, crop: crop))

                Text("\(crop.width) x \(crop.height)")
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .position(x: cropFrame.midX, y: max(videoFrame.minY + 16, cropFrame.minY - 14))
                    .allowsHitTesting(false)
                    .opacity(allowsSelection ? 1 : 0)

                if allowsSelection {
                    ForEach(CropDragHandle.resizeHandles) { handle in
                        CropHandleView(handle: handle)
                            .position(handle.point(in: cropFrame))
                            .gesture(cropGesture(handle: handle, scale: scale, crop: crop))
                    }
                }
            }
        }
    }

    private func fittedVideoFrame(in container: CGSize) -> CGRect {
        guard sourceWidth > 0, sourceHeight > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }

        let sourceRatio = CGFloat(sourceWidth) / CGFloat(sourceHeight)
        let containerRatio = container.width / container.height
        let size: CGSize

        if containerRatio > sourceRatio {
            size = CGSize(width: container.height * sourceRatio, height: container.height)
        } else {
            size = CGSize(width: container.width, height: container.width / sourceRatio)
        }

        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func cropFrame(for crop: CropRectangle, in videoFrame: CGRect) -> CGRect {
        let scaleX = videoFrame.width / CGFloat(sourceWidth)
        let scaleY = videoFrame.height / CGFloat(sourceHeight)
        return CGRect(
            x: videoFrame.minX + CGFloat(crop.x) * scaleX,
            y: videoFrame.minY + CGFloat(crop.y) * scaleY,
            width: CGFloat(crop.width) * scaleX,
            height: CGFloat(crop.height) * scaleY
        )
    }

    private func cropScale(in videoFrame: CGRect) -> CGSize {
        CGSize(
            width: videoFrame.width / CGFloat(sourceWidth),
            height: videoFrame.height / CGFloat(sourceHeight)
        )
    }

    private func selectionGesture(videoFrame: CGRect, scale: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if selectionStart == nil { selectionStart = value.startLocation }
                guard let start = selectionStart else { return }
                let current = value.location
                let left = max(videoFrame.minX, min(start.x, current.x))
                let top = max(videoFrame.minY, min(start.y, current.y))
                let right = min(videoFrame.maxX, max(start.x, current.x))
                let bottom = min(videoFrame.maxY, max(start.y, current.y))
                guard right - left >= 4, bottom - top >= 4 else { return }
                onChange(CropRectangle(
                    x: Int(((left - videoFrame.minX) / scale.width).rounded()).evenForVideo,
                    y: Int(((top - videoFrame.minY) / scale.height).rounded()).evenForVideo,
                    width: Int(((right - left) / scale.width).rounded()).evenForVideo,
                    height: Int(((bottom - top) / scale.height).rounded()).evenForVideo
                ))
            }
            .onEnded { _ in selectionStart = nil }
    }

    private func cropGesture(handle: CropDragHandle, scale: CGSize, crop: CropRectangle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil { dragStart = crop }
                guard let dragStart else { return }
                let deltaX = Int((value.translation.width / max(scale.width, 0.0001)).rounded())
                let deltaY = Int((value.translation.height / max(scale.height, 0.0001)).rounded())
                onChange(adjustedCrop(from: dragStart, handle: handle, deltaX: deltaX, deltaY: deltaY))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func adjustedCrop(from start: CropRectangle, handle: CropDragHandle, deltaX: Int, deltaY: Int) -> CropRectangle {
        let minimumSize = 16
        var left = start.x
        var top = start.y
        var right = start.x + start.width
        var bottom = start.y + start.height

        switch handle {
        case .move:
            let width = right - left
            let height = bottom - top
            left = max(0, min(sourceWidth - width, start.x + deltaX))
            top = max(0, min(sourceHeight - height, start.y + deltaY))
            right = left + width
            bottom = top + height
        case .topLeft:
            left = max(0, min(right - minimumSize, start.x + deltaX))
            top = max(0, min(bottom - minimumSize, start.y + deltaY))
        case .top:
            top = max(0, min(bottom - minimumSize, start.y + deltaY))
        case .topRight:
            right = min(sourceWidth, max(left + minimumSize, start.x + start.width + deltaX))
            top = max(0, min(bottom - minimumSize, start.y + deltaY))
        case .right:
            right = min(sourceWidth, max(left + minimumSize, start.x + start.width + deltaX))
        case .bottomRight:
            right = min(sourceWidth, max(left + minimumSize, start.x + start.width + deltaX))
            bottom = min(sourceHeight, max(top + minimumSize, start.y + start.height + deltaY))
        case .bottom:
            bottom = min(sourceHeight, max(top + minimumSize, start.y + start.height + deltaY))
        case .bottomLeft:
            left = max(0, min(right - minimumSize, start.x + deltaX))
            bottom = min(sourceHeight, max(top + minimumSize, start.y + start.height + deltaY))
        case .left:
            left = max(0, min(right - minimumSize, start.x + deltaX))
        }

        let evenLeft = left.evenForVideo
        let evenTop = top.evenForVideo
        let evenRight = max(evenLeft + 2, right.evenForVideo)
        let evenBottom = max(evenTop + 2, bottom.evenForVideo)

        return CropRectangle(
            x: max(0, min(evenLeft, sourceWidth - 2)),
            y: max(0, min(evenTop, sourceHeight - 2)),
            width: max(2, min(evenRight, sourceWidth) - max(0, min(evenLeft, sourceWidth - 2))),
            height: max(2, min(evenBottom, sourceHeight) - max(0, min(evenTop, sourceHeight - 2)))
        )
    }
}

private struct CropGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let thirdWidth = geometry.size.width / 3
                let thirdHeight = geometry.size.height / 3
                for index in 1...2 {
                    let x = thirdWidth * CGFloat(index)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))

                    let y = thirdHeight * CGFloat(index)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.55), lineWidth: 0.75)
        }
    }
}

private struct CropHandleView: View {
    var handle: CropDragHandle

    var body: some View {
        ZStack {
            Color.clear

            RoundedRectangle(cornerRadius: 2)
                .fill(.white)
                .frame(width: handle.isCorner ? 12 : 18, height: handle.isCorner ? 12 : 7)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(.black.opacity(0.65), lineWidth: 1)
                }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
}

private enum CropDragHandle: String, CaseIterable, Identifiable {
    case move
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    static let resizeHandles: [CropDragHandle] = [
        .topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left
    ]

    var id: String { rawValue }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            true
        default:
            false
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .move:
            CGPoint(x: rect.midX, y: rect.midY)
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

private extension Int {
    var evenForVideo: Int {
        self - (self % 2)
    }
}
