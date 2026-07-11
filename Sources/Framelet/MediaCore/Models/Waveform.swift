import Foundation

struct WaveformSample: Codable, Hashable, Sendable {
    var time: Double
    var minimum: Float
    var maximum: Float
}

struct Waveform: Codable, Hashable, Sendable {
    var duration: Double
    var samples: [WaveformSample]
}
