import Foundation
import AVFoundation
import Combine

@MainActor
final class MusicPlayerService: ObservableObject {
    static let shared = MusicPlayerService()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentIndex: Int = 0
    @Published var volume: Float = 0.75 {
        didSet {
            if !isDucked {
                player?.volume = volume
            }
        }
    }

    private var player: AVAudioPlayer?
    private var library: MusicLibraryService?
    private var isDucked = false

    private init() {
        // Zawsze podłącz współdzieloną bibliotekę — komendy głosowe działają bez czekania na onAppear.
        library = MusicLibraryService.shared
    }

    var currentTrack: MusicTrack? {
        let tracks = activeTracks
        guard !tracks.isEmpty, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    var hasTracks: Bool { !activeTracks.isEmpty }

    private var activeTracks: [MusicTrack] {
        (library ?? MusicLibraryService.shared).tracks
    }

    func bind(library: MusicLibraryService) {
        self.library = library
        // Utrzymaj indeks w zakresie po imporcie / usunięciu
        if currentIndex >= activeTracks.count {
            currentIndex = 0
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    @discardableResult
    func play() -> Bool {
        let tracks = activeTracks
        guard !tracks.isEmpty else {
            isPlaying = false
            return false
        }
        if currentIndex >= tracks.count { currentIndex = 0 }
        if player == nil {
            load(trackAt: currentIndex)
        }
        guard player != nil else {
            isPlaying = false
            return false
        }
        configureSession()
        player?.volume = isDucked ? duckedVolume : volume
        player?.play()
        isPlaying = true
        notifyControlsChanged()
        return true
    }

    func pause() {
        player?.pause()
        isPlaying = false
        notifyControlsChanged()
    }

    /// Przesuń na kolejny utwór. `andPlay` — od razu odtwarzaj (komendy głosowe).
    @discardableResult
    func next(andPlay: Bool = false) -> Bool {
        let tracks = activeTracks
        guard !tracks.isEmpty else { return false }
        currentIndex = (currentIndex + 1) % tracks.count
        load(trackAt: currentIndex)
        if andPlay || isPlaying {
            return play()
        }
        notifyControlsChanged()
        return true
    }

    /// Cofnij na poprzedni. `andPlay` — od razu odtwarzaj (komendy głosowe).
    @discardableResult
    func previous(andPlay: Bool = false) -> Bool {
        let tracks = activeTracks
        guard !tracks.isEmpty else { return false }
        currentIndex = (currentIndex - 1 + tracks.count) % tracks.count
        load(trackAt: currentIndex)
        if andPlay || isPlaying {
            return play()
        }
        notifyControlsChanged()
        return true
    }

    func play(track: MusicTrack) {
        let tracks = activeTracks
        guard let index = tracks.firstIndex(of: track) else { return }
        currentIndex = index
        load(trackAt: index)
        play()
    }

    /// Ścisza muzykę gdy Drive Mate mówi — nadal gra cicho w tle.
    func duckForAssistant(_ shouldDuck: Bool, autoMuteEnabled: Bool = true) {
        guard autoMuteEnabled else {
            if isDucked {
                isDucked = false
                player?.volume = volume
            }
            return
        }
        isDucked = shouldDuck
        player?.volume = shouldDuck ? duckedVolume : volume
    }

    private var duckedVolume: Float {
        max(0.08, volume * 0.28)
    }

    private func load(trackAt index: Int) {
        let tracks = activeTracks
        guard tracks.indices.contains(index) else {
            player = nil
            isPlaying = false
            return
        }
        let track = tracks[index]
        do {
            player = try AVAudioPlayer(contentsOf: track.fileURL)
            player?.prepareToPlay()
            player?.volume = isDucked ? duckedVolume : volume
            player?.delegate = PlayerDelegate.shared
            PlayerDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.next(andPlay: true)
                }
            }
        } catch {
            player = nil
            isPlaying = false
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }

    private func notifyControlsChanged() {
        NotificationCenter.default.post(name: .driveMateDidControlMusic, object: nil)
    }
}

/// AVAudioPlayerDelegate must be an NSObject; kept tiny and shared.
final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    static let shared = PlayerDelegate()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
