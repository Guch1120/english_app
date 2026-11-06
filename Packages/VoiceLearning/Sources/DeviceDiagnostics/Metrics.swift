import Foundation
public struct InferenceMetrics: Codable, Sendable {
    public let elapsedSeconds: Double
    public let audioSeconds: Double?
    public let peakMemoryBytes: UInt64?
    public var realTimeFactor: Double? {
        guard let audioSeconds, audioSeconds > 0 else { return nil }
        return elapsedSeconds / audioSeconds
    }
    public init(elapsedSeconds: Double, audioSeconds: Double? = nil, peakMemoryBytes: UInt64? = nil) {
        self.elapsedSeconds = elapsedSeconds; self.audioSeconds = audioSeconds; self.peakMemoryBytes = peakMemoryBytes
    }
}
