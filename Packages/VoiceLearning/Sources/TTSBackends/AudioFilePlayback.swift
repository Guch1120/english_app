#if os(iOS)
import AVFoundation
import SpeechCore
@MainActor public final class AudioFilePlayback {
    private var player: AVAudioPlayer?
    public init() {}
    public func play(_ asset: AudioAsset, rate: Double, repeating: Bool) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let player = try AVAudioPlayer(contentsOf: asset.url)
        player.enableRate = true; player.rate = Float(rate); player.numberOfLoops = repeating ? -1 : 0
        player.prepareToPlay()
        guard player.play() else { throw CocoaError(.fileReadUnknown) }
        self.player = player
    }
    public func pause() { player?.pause() }
    public func resume() { player?.play() }
    public func stop() { player?.stop(); player = nil }
    public func setRate(_ rate: Double) { player?.rate = Float(rate) }
    public func setRepeating(_ repeating: Bool) { player?.numberOfLoops = repeating ? -1 : 0 }
}
#endif
