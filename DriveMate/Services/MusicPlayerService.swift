import Foundation
import AVFoundation
import Combine

@MainActor
final class MusicPlayerService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentIndex: Int = 0
    @Published var volume: Float = 0.75 {
        didSet { player?.volume = volume }
    }

    private var player: AVAudioPlayer?
    private var library: MusicLibraryService?
    private var endObserver: NSObjectProtocol?

    var currentTrack: MusicTrack? {
        guard let library, !library.tracks.isEmpty,
              library.tracks.indices.contains(currentIndex) else { return nil }
        return library.tracks[currentIndex]
    }

    func bind(library: MusicLibraryService) {
        self.library = library
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let library, !library.tracks.isEmpty else { return }
        if player == nil {
            load(trackAt: currentIndex)
        }
        configureSession()
        player?.volume = volume
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func next() {
        guard let library, !library.tracks.isEmpty else { return }
        currentIndex = (currentIndex + 1) % library.tracks.count
        load(trackAt: currentIndex)
        if isPlaying { play() }
    }

    func previous() {
        guard let library, !library.tracks.isEmpty else { return }
        currentIndex = (currentIndex - 1 + library.tracks.count) % library.tracks.count
        load(trackAt: currentIndex)
        if isPlaying { play() }
    }

    func play(track: MusicTrack) {
        guard let library,
              let index = library.tracks.firstIndex(of: track) else { return }
        currentIndex = index
        load(trackAt: index)
        play()
    }

    func duckForAssistant(_ shouldDuck: Bool, autoMuteEnabled: Bool) {
        guard autoMuteEnabled else { return }
        player?.volume = shouldDuck ? max(0.05, volume * 0.15) : volume
    }

    private func load(trackAt index: Int) {
        guard let library, library.tracks.indices.contains(index) else {
            player = nil
            isPlaying = false
            return
        }
        let track = library.tracks[index]
        do {
            player = try AVAudioPlayer(contentsOf: track.fileURL)
            player?.prepareToPlay()
            player?.volume = volume
            player?.delegate = PlayerDelegate.shared
            PlayerDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.next()
                    self?.play()
                }
            }
        } catch {
            player = nil
            isPlaying = false
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers — muzyka nie jest duck’owana przez inne AV (np. przyszły asystent / recorder).
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
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
