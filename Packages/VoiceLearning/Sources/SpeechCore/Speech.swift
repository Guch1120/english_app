import Foundation
public struct AudioAsset: Sendable { public let url: URL; public let duration: Double; public let sampleRate: Double
    public init(url: URL, duration: Double, sampleRate: Double) { self.url = url; self.duration = duration; self.sampleRate = sampleRate }
}
public struct SpeechRequest: Sendable { public let text: String; public let voiceID: String
    public init(text: String, voiceID: String) { self.text = text; self.voiceID = voiceID }
}
public protocol ModelLifecycle: Sendable {
    var modelID: String { get }
    func load() async throws
    func unload() async
    func cancel() async
}
public protocol TTSService: ModelLifecycle { func synthesize(_ request: SpeechRequest) async throws -> AudioAsset }
public protocol ASRService: ModelLifecycle { func transcribe(_ audio: AudioAsset) async throws -> String }
public protocol AudioEnhancementService: ModelLifecycle { func enhance(_ audio: AudioAsset) async throws -> AudioAsset }
public actor MockASR: ASRService {
    public nonisolated let modelID = "mock-asr"
    public init() {}
    public func load() async throws { try Task.checkCancellation() }
    public func unload() async {}
    public func cancel() async {}
    public func transcribe(_ audio: AudioAsset) async throws -> String {
        try Task.checkCancellation(); return "Could you schedule the meeting for Thursday?"
    }
}

/// Playback-only system fallback; neural TTS engines produce AudioAsset separately.
@MainActor public protocol SpeechPlayback: AnyObject {
    func speak(_ text: String, speed: Double) throws
    func stop()
    func pause()
    func resume()
}
