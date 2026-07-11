import AppKit
import SwiftUI

struct TimelineViewRepresentable: NSViewRepresentable {
    var duration: Double
    var visibleStart: Double
    var visibleDuration: Double
    var currentTime: Double
    var inPoint: Double?
    var outPoint: Double?
    var segments: [Segment]
    var selectedSegmentID: Segment.ID?
    var keyframes: [Double]
    var thumbnails: [TimelineThumbnail]
    var waveform: Waveform
    var onSeek: (Double) -> Void
    var onSelect: (Segment.ID?) -> Void
    var onResizeSegment: (Segment.ID, Double?, Double?) -> Void
    var onMoveSegment: (Segment.ID, Int) -> Void
    var onPanTimeline: (Double) -> Void

    func makeNSView(context: Context) -> TimelineNSView {
        let view = TimelineNSView()
        view.onSeek = onSeek
        view.onSelect = onSelect
        view.onResizeSegment = onResizeSegment
        view.onMoveSegment = onMoveSegment
        view.onPanTimeline = onPanTimeline
        view.keyframes = keyframes
        view.thumbnails = thumbnails
        view.waveform = waveform
        view.visibleStart = visibleStart
        view.visibleDuration = visibleDuration
        return view
    }

    func updateNSView(_ nsView: TimelineNSView, context: Context) {
        nsView.duration = duration
        nsView.visibleStart = visibleStart
        nsView.visibleDuration = visibleDuration
        nsView.currentTime = currentTime
        nsView.inPoint = inPoint
        nsView.outPoint = outPoint
        nsView.segments = segments
        nsView.selectedSegmentID = selectedSegmentID
        nsView.keyframes = keyframes
        nsView.thumbnails = thumbnails
        nsView.waveform = waveform
        nsView.onSeek = onSeek
        nsView.onSelect = onSelect
        nsView.onResizeSegment = onResizeSegment
        nsView.onMoveSegment = onMoveSegment
        nsView.onPanTimeline = onPanTimeline
        nsView.needsDisplay = true
    }
}

final class TimelineNSView: NSView {
    var duration: Double = 1
    var visibleStart: Double = 0
    var visibleDuration: Double = 1
    var currentTime: Double = 0
    var inPoint: Double?
    var outPoint: Double?
    var segments: [Segment] = []
    var selectedSegmentID: Segment.ID?
    var keyframes: [Double] = []
    var thumbnails: [TimelineThumbnail] = []
    var waveform = Waveform(duration: 0, samples: [])
    var onSeek: ((Double) -> Void)?
    var onSelect: ((Segment.ID?) -> Void)?
    var onResizeSegment: ((Segment.ID, Double?, Double?) -> Void)?
    var onMoveSegment: ((Segment.ID, Int) -> Void)?
    var onPanTimeline: ((Double) -> Void)?
    private var activeDrag: TimelineDrag?
    private let thumbnailY: CGFloat = 54
    private let thumbnailHeight: CGFloat = 52
    private let segmentY: CGFloat = 122
    private let segmentHeight: CGFloat = 56
    private let waveformY: CGFloat = 194
    private let waveformHeight: CGFloat = 46
    private let edgeHitWidth: CGFloat = 8

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        drawRuler()
        drawThumbnails()
        drawKeyframes()
        drawSegmentTrack()
        drawWaveform()
        drawMarks()
        drawPlayhead()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitTestTimeline(at: point) {
            onSelect?(hit.segment.id)
            selectedSegmentID = hit.segment.id
            activeDrag = TimelineDrag(
                kind: hit.kind,
                segment: hit.segment,
                mouseDownPoint: point,
                latestPoint: point
            )
            needsDisplay = true
        } else {
            onSelect?(nil)
            onSeek?(time(for: point.x))
            activeDrag = nil
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for segment in segments {
            let rect = segmentRect(for: segment)
            addCursorRect(
                CGRect(x: rect.minX - edgeHitWidth / 2, y: rect.minY, width: edgeHitWidth, height: rect.height),
                cursor: .resizeLeftRight
            )
            addCursorRect(
                CGRect(x: rect.maxX - edgeHitWidth / 2, y: rect.minY, width: edgeHitWidth, height: rect.height),
                cursor: .resizeLeftRight
            )

            let moveWidth = rect.width - edgeHitWidth * 2
            if moveWidth > 0 {
                addCursorRect(
                    CGRect(x: rect.minX + edgeHitWidth, y: rect.minY, width: moveWidth, height: rect.height),
                    cursor: .openHand
                )
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = activeDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        drag.latestPoint = point
        activeDrag = drag

        switch drag.kind {
        case .resizeStart:
            let proposedStart = min(time(for: point.x), drag.segment.sourceEnd - 0.05)
            onResizeSegment?(drag.segment.id, proposedStart, nil)
        case .resizeEnd:
            let proposedEnd = max(time(for: point.x), drag.segment.sourceStart + 0.05)
            onResizeSegment?(drag.segment.id, nil, proposedEnd)
        case .move:
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            activeDrag = nil
            needsDisplay = true
        }

        guard let drag = activeDrag else { return }
        let point = convert(event.locationInWindow, from: nil)

        if drag.kind == .move {
            onMoveSegment?(drag.segment.id, insertionIndex(for: point.x, moving: drag.segment.id))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        guard abs(delta) > 0 else { return }
        onPanTimeline?(Double(delta / max(1, bounds.width)))
    }

    private func drawRuler() {
        let rulerRect = CGRect(x: 0, y: 0, width: bounds.width, height: 44)
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: rulerRect.maxY - 1, width: bounds.width, height: 1)).fill()

        let tickCount = max(2, Int(bounds.width / 120))
        for tick in 0...tickCount {
            let fraction = Double(tick) / Double(tickCount)
            let x = CGFloat(fraction) * bounds.width
            let time = visibleStart + fraction * safeVisibleDuration
            NSColor.secondaryLabelColor.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: 24))
            path.line(to: CGPoint(x: x, y: 42))
            path.stroke()

            let text = TimecodeFormatter.string(from: time)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            text.draw(at: CGPoint(x: min(x + 4, bounds.width - 88), y: 6), withAttributes: attributes)
        }
    }

    private func drawSegmentTrack() {
        let trackRect = CGRect(x: 12, y: segmentY - 8, width: bounds.width - 24, height: segmentHeight + 16)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 6, yRadius: 6).fill()

        for segment in segments {
            guard segment.sourceEnd >= visibleStart, segment.sourceStart <= visibleEnd else { continue }
            let rect = segmentRect(for: segment)
            color(for: segment).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()

            if segment.id == selectedSegmentID {
                NSColor.controlAccentColor.setStroke()
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
                border.lineWidth = 3
                border.stroke()
            }

            let title = "\(segment.name)  \(TimecodeFormatter.string(from: segment.duration))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            title.draw(in: rect.insetBy(dx: 8, dy: 18), withAttributes: attributes)

            drawHandles(in: rect)
        }

        if let activeDrag, activeDrag.kind == .move {
            drawMovePreview(for: activeDrag)
        }
    }

    private func drawKeyframes() {
        guard !keyframes.isEmpty else { return }
        let visibleKeyframes = keyframes.filter { $0 >= visibleStart && $0 <= visibleEnd }
        guard !visibleKeyframes.isEmpty else { return }

        let stride = max(1, visibleKeyframes.count / max(1, Int(bounds.width / 7)))
        NSColor.systemYellow.withAlphaComponent(0.45).setStroke()
        for (offset, timestamp) in visibleKeyframes.enumerated() where offset % stride == 0 {
            let x = x(for: timestamp)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: 44))
            path.line(to: CGPoint(x: x, y: 118))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawThumbnails() {
        let trackRect = CGRect(x: 12, y: thumbnailY, width: bounds.width - 24, height: thumbnailHeight)
        NSColor.black.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 5, yRadius: 5).fill()

        guard !thumbnails.isEmpty else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            "Thumbnails will appear here for playable video".draw(
                at: CGPoint(x: trackRect.minX + 10, y: trackRect.midY - 7),
                withAttributes: attributes
            )
            return
        }

        let visibleThumbnails = thumbnails.filter { $0.timestamp >= visibleStart && $0.timestamp <= visibleEnd }
        let tileWidth = max(64, min(150, bounds.width / CGFloat(max(1, visibleThumbnails.count))))
        for thumbnail in visibleThumbnails {
            let centerX = x(for: thumbnail.timestamp)
            let rect = CGRect(
                x: max(trackRect.minX, min(centerX - tileWidth / 2, trackRect.maxX - tileWidth)),
                y: trackRect.minY + 3,
                width: tileWidth - 3,
                height: trackRect.height - 6
            )
            thumbnail.image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.medium]
            )
        }

        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: trackRect, xRadius: 5, yRadius: 5).stroke()
    }

    private func drawWaveform() {
        let trackRect = CGRect(x: 12, y: waveformY, width: bounds.width - 24, height: waveformHeight)
        NSColor.black.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 5, yRadius: 5).fill()

        guard !waveform.samples.isEmpty else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            "Waveform will appear here when the media has audio".draw(
                at: CGPoint(x: trackRect.minX + 10, y: trackRect.midY - 7),
                withAttributes: attributes
            )
            NSColor.separatorColor.setStroke()
            NSBezierPath(roundedRect: trackRect, xRadius: 5, yRadius: 5).stroke()
            return
        }

        let centerY = trackRect.midY
        let halfHeight = (trackRect.height - 8) / 2
        NSColor.controlAccentColor.withAlphaComponent(0.72).setStroke()

        let visibleSamples = waveform.samples.filter { $0.time >= visibleStart && $0.time <= visibleEnd }
        let stride = max(1, visibleSamples.count / max(1, Int(bounds.width)))
        for (offset, sample) in visibleSamples.enumerated() where offset % stride == 0 {
            let x = self.x(for: sample.time)
            guard x >= trackRect.minX, x <= trackRect.maxX else { continue }
            let top = centerY - CGFloat(max(0, sample.maximum)) * halfHeight
            let bottom = centerY - CGFloat(min(0, sample.minimum)) * halfHeight
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: top))
            path.line(to: CGPoint(x: x, y: bottom))
            path.lineWidth = 1
            path.stroke()
        }

        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: trackRect, xRadius: 5, yRadius: 5).stroke()
    }

    private func drawHandles(in rect: CGRect) {
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(
            roundedRect: CGRect(x: rect.minX + 4, y: rect.minY + 12, width: 3, height: rect.height - 24),
            xRadius: 1.5,
            yRadius: 1.5
        ).fill()
        NSBezierPath(
            roundedRect: CGRect(x: rect.maxX - 7, y: rect.minY + 12, width: 3, height: rect.height - 24),
            xRadius: 1.5,
            yRadius: 1.5
        ).fill()
    }

    private func drawMovePreview(for drag: TimelineDrag) {
        let proposedIndex = insertionIndex(for: drag.latestPoint.x, moving: drag.segment.id)
        let previewX = insertionX(for: proposedIndex, moving: drag.segment.id)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: previewX, y: segmentY - 10))
        path.line(to: CGPoint(x: previewX, y: segmentY + segmentHeight + 10))
        path.lineWidth = 3
        path.stroke()
    }

    private func drawMarks() {
        if let inPoint {
            drawMarker(time: inPoint, color: .systemGreen, label: "I")
        }
        if let outPoint {
            drawMarker(time: outPoint, color: .systemOrange, label: "O")
        }
    }

    private func drawMarker(time: Double, color: NSColor, label: String) {
        let x = x(for: time)
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x, y: 44))
        path.line(to: CGPoint(x: x, y: bounds.height))
        path.lineWidth = 2
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: color
        ]
        label.draw(at: CGPoint(x: x + 4, y: 46), withAttributes: attributes)
    }

    private func drawPlayhead() {
        let x = x(for: currentTime)
        NSColor.systemRed.setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x, y: 0))
        path.line(to: CGPoint(x: x, y: bounds.height))
        path.lineWidth = 2
        path.stroke()
    }

    private func hitTestTimeline(at point: CGPoint) -> TimelineHit? {
        for segment in segments.reversed() {
            guard segment.sourceEnd >= visibleStart, segment.sourceStart <= visibleEnd else { continue }
            let rect = segmentRect(for: segment)
            guard rect.contains(point) else { continue }

            if abs(point.x - rect.minX) <= edgeHitWidth {
                return TimelineHit(segment: segment, kind: .resizeStart)
            }

            if abs(point.x - rect.maxX) <= edgeHitWidth {
                return TimelineHit(segment: segment, kind: .resizeEnd)
            }

            return TimelineHit(segment: segment, kind: .move)
        }

        return nil
    }

    private func segmentRect(for segment: Segment) -> CGRect {
        CGRect(
            x: x(for: segment.sourceStart),
            y: segmentY,
            width: max(4, x(for: segment.sourceEnd) - x(for: segment.sourceStart)),
            height: segmentHeight
        )
    }

    private func insertionIndex(for xPosition: CGFloat, moving movingID: Segment.ID) -> Int {
        let remaining = segments.filter { $0.id != movingID }
        guard !remaining.isEmpty else { return 0 }

        for (index, segment) in remaining.enumerated() {
            if xPosition < segmentRect(for: segment).midX {
                return index
            }
        }

        return remaining.count
    }

    private func insertionX(for insertionIndex: Int, moving movingID: Segment.ID) -> CGFloat {
        let remaining = segments.filter { $0.id != movingID }
        if remaining.isEmpty {
            return bounds.midX
        }
        if insertionIndex <= 0 {
            return segmentRect(for: remaining[0]).minX
        }
        if insertionIndex >= remaining.count {
            return segmentRect(for: remaining[remaining.count - 1]).maxX
        }
        let left = segmentRect(for: remaining[insertionIndex - 1]).maxX
        let right = segmentRect(for: remaining[insertionIndex]).minX
        return (left + right) / 2
    }

    private func x(for time: Double) -> CGFloat {
        guard safeVisibleDuration > 0 else { return 0 }
        return CGFloat((time - visibleStart) / safeVisibleDuration) * bounds.width
    }

    private func time(for x: CGFloat) -> Double {
        guard bounds.width > 0 else { return 0 }
        return max(0, min(duration, visibleStart + Double(x / bounds.width) * safeVisibleDuration))
    }

    private var safeVisibleDuration: Double {
        max(0.001, min(visibleDuration, max(duration, 0.001)))
    }

    private var visibleEnd: Double {
        visibleStart + safeVisibleDuration
    }

    private func color(for segment: Segment) -> NSColor {
        switch segment.colorTag {
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .red: .systemRed
        case .purple: .systemPurple
        case .blue, .none: .systemBlue
        }
    }
}

private struct TimelineHit {
    var segment: Segment
    var kind: TimelineDragKind
}

private struct TimelineDrag {
    var kind: TimelineDragKind
    var segment: Segment
    var mouseDownPoint: CGPoint
    var latestPoint: CGPoint
}

private enum TimelineDragKind {
    case resizeStart
    case resizeEnd
    case move
}
