import Foundation
import AVFoundation
import AudioToolbox

/// Krótki mechaniczny klik UI (sidebar / przyciski).
@MainActor
enum MechanicalClickSound {
    private static var player: AVAudioPlayer?
    private static var prepared = false

    static func prepare() {
        guard !prepared else { return }
        prepared = true
        guard let url = Bundle.main.url(forResource: "click_mech", withExtension: "wav") else {
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.volume = 0.55
            player = p
        } catch {
            player = nil
        }
    }

    static func play() {
        prepare()
        if let player {
            player.currentTime = 0
            // Nie rujnuj sesji muzyki — miksuj
            try? AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )
            player.play()
        } else {
            // Fallback systemowy „tik”
            AudioServicesPlaySystemSound(1104)
        }
    }
}
