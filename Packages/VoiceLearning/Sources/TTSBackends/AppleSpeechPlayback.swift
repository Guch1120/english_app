#if os(iOS)
import AVFoundation
import SpeechCore
public enum AppleSpeechError: Error { case englishVoiceUnavailable }
@MainActor public final class AppleSpeechPlayback: NSObject, SpeechPlayback, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var repeats = false
    private var repeatingText: String?
    private var repeatingSpeed: Double = 1
    private var repeatingVoice: AVSpeechSynthesisVoice?
    private var currentUtteranceID: ObjectIdentifier?
    public override init() {
        super.init()
        synthesizer.delegate = self
    }
    public func speak(_ text: String, speed: Double) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        currentUtteranceID = nil
        repeatingText = nil
        repeatingVoice = nil
        synthesizer.stopSpeaking(at: .immediate)
        repeatingText = text
        repeatingSpeed = min(1.5, max(0.5, speed))
        let utterance = AVSpeechUtterance(string: text)
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { throw AppleSpeechError.englishVoiceUnavailable }
        repeatingVoice = voice
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(repeatingSpeed)
        currentUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }
    public func setRepeating(_ repeating: Bool) { repeats = repeating }
    public func pause() { synthesizer.pauseSpeaking(at: .word) }
    public func resume() { synthesizer.continueSpeaking() }
    public func stop() {
        repeatingText = nil
        currentUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finishedID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.repeatAfterFinishing(utteranceID: finishedID)
        }
    }
    private func repeatAfterFinishing(utteranceID: ObjectIdentifier) {
        guard repeats, currentUtteranceID == utteranceID, let repeatingText, let repeatingVoice else { return }
        let next = AVSpeechUtterance(string: repeatingText)
        next.voice = repeatingVoice
        next.rate = AVSpeechUtteranceDefaultSpeechRate * Float(repeatingSpeed)
        currentUtteranceID = ObjectIdentifier(next)
        synthesizer.speak(next)
    }
}
#endif
