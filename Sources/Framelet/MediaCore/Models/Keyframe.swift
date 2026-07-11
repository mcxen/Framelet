import Foundation

struct Keyframe: Identifiable, Codable, Hashable, Sendable {
    var id: Double { timestamp }
    var timestamp: Double
    var duration: Double?
}

struct KeyframeIndex: Codable, Hashable, Sendable {
    var timestamps: [Double]

    init(_ timestamps: [Double]) {
        self.timestamps = Array(Set(timestamps.filter { $0.isFinite && $0 >= 0 })).sorted()
    }

    func nearestBefore(_ time: Double) -> Double? {
        guard !timestamps.isEmpty else { return nil }
        var low = 0
        var high = timestamps.count
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let index = low - 1
        return index >= 0 ? timestamps[index] : nil
    }

    func nearestAfter(_ time: Double) -> Double? {
        guard !timestamps.isEmpty else { return nil }
        var low = 0
        var high = timestamps.count
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low < timestamps.count ? timestamps[low] : nil
    }

    func nearest(to time: Double) -> Double? {
        let before = nearestBefore(time)
        let after = nearestAfter(time)
        switch (before, after) {
        case let (before?, after?):
            return abs(time - before) <= abs(after - time) ? before : after
        case let (before?, nil):
            return before
        case let (nil, after?):
            return after
        case (nil, nil):
            return nil
        }
    }
}
