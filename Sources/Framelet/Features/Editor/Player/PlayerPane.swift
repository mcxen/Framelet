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
                   let sourceHeight = video.height,
                   let crop = store.cropPreviewRectangle {
                    CropOverlay(
                        sourceWidth: sourceWidth,
                        sourceHeight: sourceHeight,
                        crop: crop,
                        onChange: store.setCropRectangle
                    )
                }

                if store.mediaInfo == nil {
                    ContentUnavailableView(
                        "No Media",
                        systemImage: "film",
                        description: Text("Open a file to start lossless trimming.")
                    )
                    .foregroundStyle(.secondary)
                }

                if store.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

private struct CropOverlay: View {
    var sourceWidth: Int
    var sourceHeight: Int
    var crop: CropRectangle
    var onChange: (CropRectangle) -> Void

    @State private var dragStart: CropRectangle?

    var body: some View {
        GeometryReader { geometry in
            let videoFrame = fittedVideoFrame(in: geometry.size)
            let cropFrame = cropFrame(in: videoFrame)
            let scale = cropScale(in: videoFrame)

            Path { path in
                path.addRect(CGRect(origin: .zero, size: geometry.size))
                path.addRect(cropFrame)
            }
            .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))

            Rectangle()
                .path(in: cropFrame)
                .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .contentShape(Rectangle())
                .gesture(cropGesture(handle: .move, scale: scale))

            Text("\(crop.width)x\(crop.height)")
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.yellow)
                .position(x: cropFrame.midX, y: max(videoFrame.minY + 16, cropFrame.minY - 14))

            ForEach(CropDragHandle.resizeHandles) { handle in
                CropHandleView(handle: handle)
                    .position(handle.point(in: cropFrame))
                    .gesture(cropGesture(handle: handle, scale: scale))
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

    private func cropFrame(in videoFrame: CGRect) -> CGRect {
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

    private func cropGesture(handle: CropDragHandle, scale: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = crop
                }
                guard let dragStart else { return }
                let deltaX = Int((value.translation.width / max(scale.width, 0.0001)).rounded())
                let deltaY = Int((value.translation.height / max(scale.height, 0.0001)).rounded())
                onChange(adjustedCrop(from: dragStart, handle: handle, deltaX: deltaX, deltaY: deltaY))
            }
            .onEnded { _ in
                dragStart = nil
            }
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

private struct CropHandleView: View {
    var handle: CropDragHandle

    var body: some View {
        Rectangle()
            .fill(.yellow)
            .frame(width: handle.isCorner ? 11 : 18, height: handle.isCorner ? 11 : 7)
            .overlay {
                Rectangle()
                    .stroke(.black.opacity(0.7), lineWidth: 1)
            }
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
