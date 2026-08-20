import Foundation
import AVFoundation

/// Reprodução com controle de velocidade e pulos de 15s.
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var rate: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.enableRate = true
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
            progress = 0
        } catch {
            player = nil
            duration = 0
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player.rate = rate
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        timer?.invalidate()
        timer = nil
        progress = 0
        duration = 0
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, duration))
        progress = player.currentTime
    }

    func skip(_ delta: TimeInterval) {
        seek(to: (player?.currentTime ?? 0) + delta)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if let player, isPlaying {
            player.rate = newRate
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.progress = player.currentTime
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.progress = self.duration
            self.timer?.invalidate()
        }
    }
}
