import AVFoundation
import Observation

/// Plays the test clip so the highlight can be checked by eye and ear.
@MainActor @Observable
final class ClipPlayer {
    private(set) var isPlaying = false
    private(set) var error: String?
    private var player: AVAudioPlayer?

    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    init(url: URL?) {
        guard let url else {
            error = "The test clip is missing from the app."
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
    }

    /// Jumps by `seconds` (negative to go back), keeping playback state.
    func skip(_ seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, player.currentTime + seconds), player.duration)
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }
}
