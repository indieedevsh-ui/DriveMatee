import Foundation
import Combine
import MusicKit
import UIKit

/// Koordynuje źródło muzyki (pliki lokalne / Apple Music / Spotify) zgodnie z politykami platform.
@MainActor
final class MusicSourceController: ObservableObject {
    static let shared = MusicSourceController()

    @Published private(set) var appleMusicAuthorized = false
    @Published private(set) var appleMusicStatusMessage: String?
    @Published var spotifyVoiceWarningVisible = false
    /// Stan odtwarzania widoczny w panelu (lokalne + Apple Music).
    @Published private(set) var isPlaying = false
    /// Krótki komunikat UI (np. Spotify).
    @Published var panelMessage: String?

    private var appleMusicPollTask: Task<Void, Never>?
    private var localPlayerCancellable: AnyCancellable?
    /// Apple Music spauzowane przez Hey Drive / asystenta.
    private var appleMusicHeldForAssistant = false

    private init() {
        refreshAppleMusicStatus()
        observeLocalPlayer()
        syncPlayingState()
        startAppleMusicPollingIfNeeded()
    }

    var source: MusicSource {
        MusicSource(rawValue: UserDefaults.standard.string(forKey: "musicSource") ?? "") ?? .local
    }

    var voiceMusicAllowed: Bool { source.supportsVoiceMusicCommands }

    /// Czy panel transportowy ma być aktywny.
    var controlsEnabled: Bool {
        switch source {
        case .local:
            return MusicPlayerService.shared.hasTracks
        case .appleMusic:
            return true
        case .spotify:
            // Spotify: otwieramy aplikację Spotify (App Remote wymaga Client ID z dashboardu).
            return true
        }
    }

    func select(_ source: MusicSource) {
        UserDefaults.standard.set(source.rawValue, forKey: "musicSource")
        objectWillChange.send()
        switch source {
        case .local:
            pauseAppleMusicQuietly()
            startAppleMusicPollingIfNeeded()
            syncPlayingState()
        case .appleMusic:
            MusicPlayerService.shared.pause()
            Task {
                await requestAppleMusicIfNeeded()
                startAppleMusicPollingIfNeeded()
                syncPlayingState()
            }
        case .spotify:
            MusicPlayerService.shared.pause()
            pauseAppleMusicQuietly()
            spotifyVoiceWarningVisible = true
            isPlaying = false
            startAppleMusicPollingIfNeeded()
        }
    }

    func dismissSpotifyWarning() {
        spotifyVoiceWarningVisible = false
    }

    func dismissPanelMessage() {
        panelMessage = nil
    }

    func refreshAppleMusicStatus() {
        let status = MusicAuthorization.currentStatus
        appleMusicAuthorized = (status == .authorized)
    }

    @discardableResult
    func requestAppleMusicIfNeeded() async -> Bool {
        let status = MusicAuthorization.currentStatus
        switch status {
        case .authorized:
            appleMusicAuthorized = true
            appleMusicStatusMessage = nil
            return true
        case .notDetermined:
            let result = await MusicAuthorization.request()
            appleMusicAuthorized = (result == .authorized)
            appleMusicStatusMessage = appleMusicAuthorized
                ? nil
                : "Brak dostępu do Apple Music. Włącz go w Ustawieniach systemowych."
            return appleMusicAuthorized
        case .denied, .restricted:
            appleMusicAuthorized = false
            appleMusicStatusMessage = "Apple Music jest zablokowane. Włącz dostęp w Ustawieniach iPhone’a."
            return false
        @unknown default:
            appleMusicAuthorized = false
            return false
        }
    }

    // MARK: - Panel UI (play / pauza / next / prev)

    func uiTogglePlayPause() {
        Task { await applyTransport(.toggle) }
    }

    func uiNext() {
        Task { await applyTransport(.next) }
    }

    func uiPrevious() {
        Task { await applyTransport(.previous) }
    }

    /// Odtwarzanie / sterowanie zależnie od źródła (głos + panel).
    func applyVoiceCommand(_ command: MusicPlaybackCommand) async -> String {
        switch source {
        case .spotify:
            return "Przy Spotify sterowanie głosowe muzyką jest wyłączone (polityka Spotify). Steruj odtwarzaniem w aplikacji Spotify."
        case .local, .appleMusic:
            return await applyTransport(command)
        }
    }

    @discardableResult
    private func applyTransport(_ command: MusicPlaybackCommand) async -> String {
        switch source {
        case .spotify:
            // Polityka Spotify: bez oficjalnego App Remote / Web API nie wolno zdalnie
            // sterować odtwarzaczem. Otwieramy Spotify — użytkownik steruje tam.
            openSpotify()
            panelMessage = "Odtwarzanie Spotify działa w aplikacji Spotify (wymóg polityki Spotify)."
            NotificationCenter.default.post(name: .driveMateDidControlMusic, object: nil)
            return panelMessage ?? ""

        case .local:
            let reply = MusicPlayerService.shared.executeLocalCommand(uiNormalized(command))
            syncPlayingState()
            NotificationCenter.default.post(name: .driveMateDidControlMusic, object: nil)
            return reply

        case .appleMusic:
            let ok = await requestAppleMusicIfNeeded()
            guard ok else {
                let msg = appleMusicStatusMessage
                    ?? "Nie mam dostępu do Apple Music. Połącz konto w Ustawieniach."
                panelMessage = msg
                return msg
            }
            let reply = await executeAppleMusic(command)
            syncPlayingState()
            NotificationCenter.default.post(name: .driveMateDidControlMusic, object: nil)
            return reply
        }
    }

    /// Panel: next/prev zawsze odtwarzają (w aucie sensowniejsze niż tylko przełączenie indeksu).
    private func uiNormalized(_ command: MusicPlaybackCommand) -> MusicPlaybackCommand {
        command
    }

    /// Apple Music: nie pauzujemy — ściszenie robi AVAudioSession.duckOthers przy TTS.
    func holdPlaybackForAssistant() {
        // Flaga tylko informacyjna; odtwarzanie zostaje.
        guard source == .appleMusic else { return }
        let player = ApplicationMusicPlayer.shared
        appleMusicHeldForAssistant = (player.state.playbackStatus == .playing)
    }

    /// Po TTS — nic do wznawiania (muzyka nie była pauzowana).
    func releasePlaybackAfterAssistant() {
        appleMusicHeldForAssistant = false
        syncPlayingState()
    }

    /// Otwórz Spotify — zgodnie z polityką (bez nieoficjalnego sterowania).
    func openSpotify() {
        let candidates = [
            URL(string: "spotify://"),
            URL(string: "https://open.spotify.com")
        ].compactMap { $0 }
        for url in candidates {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }

    private func executeAppleMusic(_ command: MusicPlaybackCommand) async -> String {
        let player = ApplicationMusicPlayer.shared
        MusicPlayerService.shared.pause()

        do {
            switch command {
            case .pause:
                if player.state.playbackStatus == .playing {
                    player.pause()
                    isPlaying = false
                    return "Pauza."
                }
                isPlaying = false
                return "Muzyka już jest wstrzymana."

            case .resume:
                try await ensureAppleMusicQueueAndPlay(player)
                isPlaying = true
                return "Wznawiam Apple Music."

            case .toggle:
                if player.state.playbackStatus == .playing {
                    player.pause()
                    isPlaying = false
                    return "Pauza."
                }
                try await ensureAppleMusicQueueAndPlay(player)
                isPlaying = true
                return "Wznawiam Apple Music."

            case .next:
                if player.queue.entries.isEmpty {
                    try await ensureAppleMusicQueueAndPlay(player)
                } else {
                    try await player.skipToNextEntry()
                    if player.state.playbackStatus != .playing {
                        try await player.play()
                    }
                }
                isPlaying = true
                return "Następny utwór w Apple Music."

            case .previous:
                if player.queue.entries.isEmpty {
                    try await ensureAppleMusicQueueAndPlay(player)
                } else {
                    try await player.skipToPreviousEntry()
                    if player.state.playbackStatus != .playing {
                        try await player.play()
                    }
                }
                isPlaying = true
                return "Poprzedni utwór w Apple Music."
            }
        } catch {
            panelMessage = "Apple Music: sprawdź subskrypcję i dostęp w Ustawieniach, albo odtwórz utwór w aplikacji Muzyka."
            return panelMessage ?? ""
        }
    }

    /// MusicKit: kolejka z biblioteki użytkownika (zgodne z polityką Apple Music).
    private func ensureAppleMusicQueueAndPlay(_ player: ApplicationMusicPlayer) async throws {
        if player.queue.entries.isEmpty {
            var request = MusicLibraryRequest<Song>()
            request.limit = 40
            let response = try await request.response()
            let songs = response.items
            guard !songs.isEmpty else {
                throw AppleMusicControlError.emptyLibrary
            }
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
        }
        try await player.play()
    }

    private enum AppleMusicControlError: Error {
        case emptyLibrary
    }

    private func pauseAppleMusicQuietly() {
        let player = ApplicationMusicPlayer.shared
        if player.state.playbackStatus == .playing {
            player.pause()
        }
    }

    private func observeLocalPlayer() {
        localPlayerCancellable = MusicPlayerService.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.syncPlayingState()
            }
        }
    }

    func syncPlayingState() {
        switch source {
        case .local:
            isPlaying = MusicPlayerService.shared.isPlaying
        case .appleMusic:
            isPlaying = ApplicationMusicPlayer.shared.state.playbackStatus == .playing
        case .spotify:
            isPlaying = false
        }
    }

    private func startAppleMusicPollingIfNeeded() {
        appleMusicPollTask?.cancel()
        guard source == .appleMusic else { return }
        appleMusicPollTask = Task { @MainActor in
            while !Task.isCancelled {
                syncPlayingState()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
