#if os(iOS)
import AVFoundation
import SpeechCore
public enum AppleSpeechError: Error { case englishVoiceUnavailable }
@MainActor public final class AppleSpeechPlayback: SpeechPlayback {
    private let synthesizer = AVSpeechSynthesizer()
    public init() {}
    public func speak(_ text: String, speed: Double) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { throw AppleSpeechError.englishVoiceUnavailable }
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(min(1.5, max(0.5, speed)))
        synthesizer.speak(utterance)
    }
    public func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
#endif
