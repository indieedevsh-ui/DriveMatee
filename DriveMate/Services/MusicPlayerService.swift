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
    /// Zapamiętaj, że to my spauzowaliśmy przy Hey Drive — potem wznów płynnie.
    private var pausedForAssistant = false
    private var fadeTask: Task<Void, Never>?

    private init() {
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
        if currentIndex >= activeTracks.count {
            currentIndex = 0
        }
    }

    func togglePlayPause() {
        // Panel / stary kod — kieruj przez źródło (Apple Music / lokalne / Spotify).
        if MusicSourceController.shared.source != .local {
            MusicSourceController.shared.uiTogglePlayPause()
            return
        }
        if isPlaying {
            pause()
        } else {
            _ = play()
        }
    }

    @discardableResult
    func play() -> Bool {
        let tracks = activeTracks
        guard !tracks.isEmpty else {
            isPlaying = false
            objectWillChange.send()
            return false
        }
        if currentIndex >= tracks.count { currentIndex = 0 }

        // Zawsze przeładuj, gdy brak playera albo plik się zmienił.
        if player == nil || player?.url != tracks[currentIndex].fileURL {
            load(trackAt: currentIndex)
        }
        guard let player else {
            isPlaying = false
            objectWillChange.send()
            return false
        }
        configureSession()
        // Ręczne play anuluje „pauzę dla asystenta”.
        if pausedForAssistant || isDucked {
            fadeTask?.cancel()
            pausedForAssistant = false
            isDucked = false
        }
        player.volume = volume
        let started = player.play()
        isPlaying = started
        objectWillChange.send()
        notifyControlsChanged()
        MusicSourceController.shared.syncPlayingState()
        return started
    }

    func pause() {
        player?.pause()
        isPlaying = false
        objectWillChange.send()
        notifyControlsChanged()
        MusicSourceController.shared.syncPlayingState()
    }

    /// Zatrzymaj zewnętrzne źródła gdy wracamy do lokalnych plików.
    func pauseExternalIfNeeded() {
        // Apple Music pauzuje MusicSourceController.
    }

    /// Komendy dla lokalnej biblioteki plików (głos + panel).
    func executeLocalCommand(_ command: MusicPlaybackCommand) -> String {
        bind(library: MusicLibraryService.shared)
        MusicLibraryService.shared.load()

        guard hasTracks else {
            notifyControlsChanged()
            return "Nie mam utworów — dodaj muzykę w ustawieniach (Wgraj Muzykę)."
        }

        switch command {
        case .pause:
            if !isPlaying { return "Muzyka już jest wstrzymana." }
            pause()
            return "Pauza."
        case .resume:
            if play(), let name = currentTrack?.name { return "Wznawiam \(name)." }
            return "Nie udało się odtworzyć utworu."
        case .toggle:
            if isPlaying {
                pause()
                return "Pauza."
            }
            if play(), let name = currentTrack?.name { return "Wznawiam \(name)." }
            return "Nie udało się odtworzyć utworu."
        case .next:
            if next(andPlay: true), let name = currentTrack?.name { return "Następny utwór: \(name)." }
            return "Nie udało się przełączyć utworu."
        case .previous:
            if previous(andPlay: true), let name = currentTrack?.name { return "Poprzedni utwór: \(name)." }
            return "Nie udało się przełączyć utworu."
        }
    }

    @discardableResult
    func next(andPlay: Bool = false) -> Bool {
        if MusicSourceController.shared.source != .local {
            MusicSourceController.shared.uiNext()
            return true
        }
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

    @discardableResult
    func previous(andPlay: Bool = false) -> Bool {
        if MusicSourceController.shared.source != .local {
            MusicSourceController.shared.uiPrevious()
            return true
        }
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
        // Odtwarzanie z listy w ustawieniach = lokalne źródło.
        UserDefaults.standard.set(MusicSource.local.rawValue, forKey: "musicSource")
        let tracks = activeTracks
        guard let index = tracks.firstIndex(of: track) else { return }
        currentIndex = index
        load(trackAt: index)
        _ = play()
    }

    /// Hey Drive / asystent: płynnie pauzuj; po odpowiedzi — płynnie wznów.
    func duckForAssistant(_ shouldDuck: Bool, autoMuteEnabled: Bool = true) {
        guard autoMuteEnabled else {
            if isDucked || pausedForAssistant {
                fadeTask?.cancel()
                isDucked = false
                pausedForAssistant = false
                player?.volume = volume
            }
            return
        }
        if shouldDuck {
            holdMusicForAssistant()
        } else {
            releaseMusicAfterAssistant()
        }
    }

    /// Płynne wyciszenie → pauza (lokalne + Apple Music).
    private func holdMusicForAssistant() {
        fadeTask?.cancel()
        isDucked = true
        MusicSourceController.shared.holdPlaybackForAssistant()

        guard MusicSourceController.shared.source == .local else { return }
        guard let player, player.isPlaying || isPlaying else { return }

        let startVol = player.volume
        fadeTask = Task { @MainActor in
            let steps = 10
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let t = Float(step) / Float(steps)
                player.volume = startVol * (1 - t)
                try? await Task.sleep(nanoseconds: 28_000_000)
            }
            guard !Task.isCancelled else { return }
            player.pause()
            pausedForAssistant = true
            isPlaying = false
            objectWillChange.send()
            MusicSourceController.shared.syncPlayingState()
        }
    }

    /// Wznów odtwarzanie z płynnym fade-in po asystencie.
    private func releaseMusicAfterAssistant() {
        fadeTask?.cancel()
        isDucked = false
        MusicSourceController.shared.releasePlaybackAfterAssistant()

        guard MusicSourceController.shared.source == .local else {
            pausedForAssistant = false
            return
        }
        guard pausedForAssistant else {
            player?.volume = volume
            return
        }
        pausedForAssistant = false

        configureSession()
        guard let player else { return }
        player.volume = 0
        let started = player.play()
        isPlaying = started
        objectWillChange.send()
        MusicSourceController.shared.syncPlayingState()
        guard started else {
            player.volume = volume
            return
        }

        let target = volume
        fadeTask = Task { @MainActor in
            let steps = 12
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let t = Float(step) / Float(steps)
                player.volume = target * t
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            guard !Task.isCancelled else { return }
            player.volume = target
            notifyControlsChanged()
        }
    }

    /// Przywróć sesję playback bez przerywania trwającego utworu (Recorder / zakładki).
    func ensurePlaybackSessionCompatible() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
        // Jeśli graliśmy i silnik nadal ma playera — upewnij się, że nie stoi przez sesję.
        if isPlaying, let player, !player.isPlaying, !pausedForAssistant, !isDucked {
            player.volume = volume
            _ = player.play()
        }
    }

    private func load(trackAt index: Int) {
        let tracks = activeTracks
        guard tracks.indices.contains(index) else {
            player = nil
            isPlaying = false
            return
        }
        let track = tracks[index]
        let url = track.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            player = nil
            isPlaying = false
            return
        }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.prepareToPlay()
            audio.volume = volume
            audio.delegate = PlayerDelegate.shared
            player = audio
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
        // mixWithOthers — nie wyciszaj systemu/TTS; muzykę przy asystencie ściszamy ręcznie.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }

    private func notifyControlsChanged() {
        NotificationCenter.default.post(name: .driveMateDidControlMusic, object: nil)
    }
}

final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    static let shared = PlayerDelegate()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
