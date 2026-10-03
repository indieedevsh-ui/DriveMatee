import Foundation
import FoundationModels
import AVFoundation
import Combine
import SwiftUI

/// Asystent Drive Mate: ASR (PL) → Foundation Model + tools → sterowanie aplikacją.
/// Lokalny router działa zawsze jako szybka / awaryjna ścieżka.
@MainActor
final class DriveMateAssistant: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var reply: String = ""
    @Published private(set) var isModelReady = false
    @Published private(set) var isAvatarVisible = false
    @Published private(set) var speechGlow: CGFloat = 0
    /// Skąd poszła ostatnia odpowiedź (FM / lokalnie) — diagnostyka.
    @Published private(set) var lastCommandSource: String = ""
    @Published var lastError: String?
    /// 0…1 — poziom mikrofonu (fale dyktafonu).
    @Published private(set) var audioLevel: CGFloat = 0
    /// Poświata krawędzi jak Siri (płynne włączanie przy słuchaniu).
    @Published private(set) var siriGlowIntensity: CGFloat = 0
    /// Ciche nasłuchiwanie „Hey Drive” podczas nawigacji.
    @Published private(set) var isWakeListening = false

    var avatarMood: DriveMateAvatarMood {
        switch state {
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .speaking
        default: .idle
        }
    }

    private var session: LanguageModelSession?
    /// CoreLM — osobna sesja do strukturalnego rozumienia komend.
    private var coreLMSession: LanguageModelSession?
    /// Czat bez tools — uczciwe odpowiedzi na luźne pytania.
    private var chatSession: LanguageModelSession?
    private let asr = PolishSpeechRecognizer()
    private let synthesizer = AVSpeechSynthesizer()
    private var hideAvatarTask: Task<Void, Never>?
    private var speechGlowTask: Task<Void, Never>?
    private var siriGlowTask: Task<Void, Never>?
    private var wakeRestartTask: Task<Void, Never>?
    private var keepListeningAfterSpeech = false
    /// Włączone przez cały czas aktywnej nawigacji.
    private var navigationWakeEnabled = false
    /// Pełne przechwytywanie komendy (po wake / przycisku) — nie restartuj wake.
    private var isCapturingCommand = false

    private weak var settings: AppSettings?
    private weak var music: MusicPlayerService?

    private let wakePhrases = [
        "hey drive mate", "hej drive mate", "hey drivemate", "hej drivemate",
        "hey drive", "hei drive", "hej drive", "ej drive", "ok drive",
        "hej drajw", "hey drajw", "hej draj", "hey draj", "ej drajw",
        "drive mate", "drivemate", "hej drajwmejt", "hey drajwmejt"
    ]

    override init() {
        super.init()
        synthesizer.delegate = self
        wireASR()
    }

    func configure(
        settings: AppSettings,
        music: MusicPlayerService,
        navigation: MapKitNavigationService,
        location: LocationSpeedService,
        mapState: NavigationMapState
    ) {
        self.settings = settings
        self.music = music
        navigation.mapState = mapState
        navigation.location = location
        bootstrapSession()
    }

    // MARK: - Foundation Model

    func bootstrapSession() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            isModelReady = true
            session = LanguageModelSession(
                model: model,
                tools: [
                    FindPlaceTool(),
                    PlanBestRouteTool(),
                    TrafficRiskTool(),
                    StreetInsightTool()
                ],
                instructions: """
                    Jesteś Drive Mate — asystent głosowy w samochodzie.
                    Odpowiadaj po polsku, naturalnie, max 2 zdania.

                    Zasady:
                    - NIGDY nie zmyślaj tras, ETA, adresów ani wyników mapy.
                    - Jeśli nie umiesz czegoś zrobić — powiedz wprost.
                    - Nie losuj miejsc ani odpowiedzi.

                    Nawigacja:
                    - Najpierw findPlace dla celu.
                    - Jeśli kierowca podał start (moja lokalizacja / konkretne miejsce) — potem planBestRoute.
                    - Jeśli podał TYLKO cel — NIE wołaj planBestRoute; zapytaj:
                      „Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?”

                    Korki → assessTrafficRisk. Ulica → streetInsight. Jedzenie → zasugeruj komendę głosową o restauracji.
                    """
            )
            coreLMSession = CoreLM.makeUnderstandingSession()
            chatSession = CoreLM.makeChatSession()
            state = .idle
            reply = asr.supportsOnDevice
                ? "Drive Mate AI gotowy (CoreLM + ASR)."
                : "Drive Mate AI gotowy (CoreLM)."
        case .unavailable(let reason):
            isModelReady = false
            session = nil
            coreLMSession = nil
            chatSession = nil
            let message: String
            switch reason {
            case .deviceNotEligible:
                message = "Model AI niedostępny — używam lokalnych komend głosowych."
            case .appleIntelligenceNotEnabled:
                message = "Włącz Apple Intelligence dla CoreLM. Lokalne komendy działają."
            case .modelNotReady:
                message = "Model się ładuje — lokalne komendy głosowe działają."
            @unknown default:
                message = "Tryb lokalnych komend głosowych."
            }
            state = .idle
            reply = message
        }
    }

    // MARK: - Public API

    func summon() { activateListening() }

    /// Włącz / wyłącz ciągłe nasłuchiwanie „Hey Drive” na czas nawigacji.
    func setNavigationWakeListening(_ enabled: Bool) {
        navigationWakeEnabled = enabled
        if enabled {
            scheduleWakeSpotting(after: 0.45)
        } else {
            wakeRestartTask?.cancel()
            isWakeListening = false
            if !isCapturingCommand, state == .listening {
                asr.cancel()
                state = .idle
                fadeSiriGlow(to: 0, duration: 0.4)
            }
        }
    }

    func dismissAvatar() {
        hideAvatarTask?.cancel()
        speechGlowTask?.cancel()
        withAnimation(.easeOut(duration: 0.35)) { speechGlow = 0 }
        fadeSiriGlow(to: 0, duration: 0.55)
        withAnimation(.spring(response: 0.72, dampingFraction: 0.88)) {
            isAvatarVisible = false
        }
        synthesizer.stopSpeaking(at: .immediate)
        if isWakeListening {
            // Nie kasuj wake-spot przy chowaniu awatara podczas nawigacji.
        } else {
            asr.cancel()
            audioLevel = 0
            state = .idle
        }
        isCapturingCommand = false
        restorePlaybackSession()
        if navigationWakeEnabled {
            scheduleWakeSpotting(after: 0.35)
        }
    }

    func toggleListening() {
        if !isAvatarVisible {
            activateListening()
            return
        }
        if state == .listening, !isWakeListening {
            let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            asr.stop(submit: hasText)
            audioLevel = 0
            isCapturingCommand = false
            if !hasText {
                state = .idle
                fadeSiriGlow(to: 0, duration: 0.55)
                scheduleHideAvatar()
                resumeWakeIfNeeded()
            }
        } else if state == .idle || state == .speaking || isWakeListening {
            if state == .speaking { synthesizer.stopSpeaking(at: .immediate) }
            activateListening()
        }
    }

    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        wakeRestartTask?.cancel()
        if isWakeListening {
            asr.cancel()
            isWakeListening = false
        }
        isCapturingCommand = true
        showAvatar()
        transcript = trimmed
        Task { await handleCommand(stripWakeWord(from: trimmed)) }
    }

    /// Pytanie TTS + ponowne słuchanie (np. potwierdzenie restauracji).
    func promptAndListen(_ text: String) {
        wakeRestartTask?.cancel()
        if isWakeListening {
            asr.cancel()
            isWakeListening = false
        }
        isCapturingCommand = true
        hideAvatarTask?.cancel()
        showAvatar()
        reply = text
        fadeSiriGlow(to: 0.8, duration: 0.35)
        speak(text, keepListeningAfter: true, faster: true)
    }

    func announceNavigation(_ text: String) {
        // Podczas nawigacji bez oczu / awatara — tylko komunikat głosowy.
        // Wstrzymaj wake-spot na czas TTS, potem wznów.
        wakeRestartTask?.cancel()
        if isWakeListening {
            asr.cancel()
            isWakeListening = false
        }
        reply = text
        speak(text, keepListeningAfter: false)
    }

    // MARK: - Listening

    private func wireASR() {
        asr.onPartialTranscript = { [weak self] text in
            guard let self else { return }
            self.transcript = text
            // Podczas wake-spot nie pulsuj UI — ciche nasłuchiwanie.
            if !self.isWakeListening {
                self.pulseSpeechGlow()
            }
        }
        asr.onFinalTranscript = { [weak self] text in
            guard let self else { return }
            self.transcript = text
            self.audioLevel = 0

            if self.isWakeListening, !self.isCapturingCommand {
                self.handleWakeSpottingTranscript(text)
                return
            }

            self.music?.duckForAssistant(false, autoMuteEnabled: self.settings?.autoMuteEnabled ?? true)
            self.restorePlaybackSession()
            let hasWake = self.containsWakeWord(text)
            let stripped = self.stripWakeWord(from: text)
            let command = hasWake ? stripped : text
            guard !command.isEmpty else {
                if hasWake {
                    self.activateListening()
                } else {
                    self.state = .idle
                    self.resumeWakeIfNeeded()
                }
                return
            }
            Task { await self.handleCommand(command) }
        }
        asr.onAudioLevel = { [weak self] level in
            guard let self else { return }
            if self.isWakeListening { return }
            // Tylko fale — nie ruszaj poświaty (to powodowało zacięcia).
            if abs(level - self.audioLevel) > 0.04 {
                self.audioLevel = level
            }
        }
        asr.onWakeSpotNeedsRestart = { [weak self] in
            guard let self else { return }
            self.isWakeListening = false
            if self.state == .listening { self.state = .idle }
            self.scheduleWakeSpotting(after: 0.25)
        }
    }

    private func handleWakeSpottingTranscript(_ text: String) {
        let hasWake = containsWakeWord(text)
        let stripped = stripWakeWord(from: text)
        isWakeListening = false

        guard hasWake else {
            // Szum / rozmowa bez wake — wznów ciche nasłuchiwanie.
            scheduleWakeSpotting(after: 0.2)
            return
        }

        if stripped.isEmpty {
            activateListening()
        } else {
            music?.duckForAssistant(false, autoMuteEnabled: settings?.autoMuteEnabled ?? true)
            restorePlaybackSession()
            Task { await handleCommand(stripped) }
        }
    }

    private func scheduleWakeSpotting(after delay: TimeInterval) {
        wakeRestartTask?.cancel()
        guard navigationWakeEnabled else { return }
        wakeRestartTask = Task { @MainActor in
            let ns = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            startWakeSpottingIfNeeded()
        }
    }

    private func startWakeSpottingIfNeeded() {
        guard navigationWakeEnabled else { return }
        guard !isCapturingCommand else { return }
        guard !isWakeListening else { return }
        switch state {
        case .thinking, .speaking: return
        case .listening: return // pełne słuchanie komendy
        case .unavailable: return
        default: break
        }

        isWakeListening = true
        isCapturingCommand = false
        state = .listening
        transcript = ""
        // Bez awatara / glow — ciche tło.
        fadeSiriGlow(to: 0, duration: 0.2)

        Task {
            await asr.start(mode: .wakeSpot)
            if case .unavailable = asr.status {
                isWakeListening = false
                state = .idle
                // Spróbuj później (np. brak uprawnień tymczasowo).
                scheduleWakeSpotting(after: 2.0)
            }
        }
    }

    private func resumeWakeIfNeeded() {
        guard navigationWakeEnabled else { return }
        scheduleWakeSpotting(after: 0.4)
    }

    private func activateListening() {
        wakeRestartTask?.cancel()
        hideAvatarTask?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        keepListeningAfterSpeech = false
        isWakeListening = false
        isCapturingCommand = true
        asr.cancel()
        showAvatar()
        reply = "Słucham…"
        transcript = ""
        audioLevel = 0
        state = .listening
        // Jedna płynna animacja SwiftUI — bez krokowego przerysowywania
        fadeSiriGlow(to: 1, duration: 0.55)

        if settings?.autoMuteEnabled == true {
            music?.duckForAssistant(true, autoMuteEnabled: true)
        }

        // ASR po krótkim oddechu UI, żeby nie zacinać animacji wejścia
        Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, state == .listening, isCapturingCommand else { return }
            await asr.start(mode: .command)
            if case .unavailable(let msg) = asr.status {
                lastError = msg
                state = .idle
                isCapturingCommand = false
                audioLevel = 0
                fadeSiriGlow(to: 0, duration: 0.4)
                restorePlaybackSession()
                resumeWakeIfNeeded()
            }
        }
    }

    private func showAvatar() {
        hideAvatarTask?.cancel()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.76)) {
            isAvatarVisible = true
        }
    }

    private func scheduleHideAvatar() {
        hideAvatarTask?.cancel()
        hideAvatarTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, state == .idle else { return }
            withAnimation(.spring(response: 0.72, dampingFraction: 0.9)) {
                isAvatarVisible = false
            }
        }
    }

    private func pulseSpeechGlow() {
        speechGlowTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) { speechGlow = 1 }
        speechGlowTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.55)) { speechGlow = 0 }
        }
    }

    // MARK: - Command pipeline

    private func handleCommand(_ prompt: String) async {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            state = .idle
            isCapturingCommand = false
            fadeSiriGlow(to: 0, duration: 0.6)
            scheduleHideAvatar()
            resumeWakeIfNeeded()
            return
        }

        wakeRestartTask?.cancel()
        isWakeListening = false
        isCapturingCommand = true
        showAvatar()
        state = .thinking
        reply = ""
        speechGlowTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { speechGlow = 0 }

        let result = await VoiceCommandProcessor.process(
            transcript: cleaned,
            toolSession: session,
            understandingSession: coreLMSession,
            chatSession: chatSession,
            modelReady: isModelReady
        )

        lastCommandSource = result.source.rawValue
        reply = result.reply

        if result.awaitFurtherInput {
            // Od razu pytanie o start — krótka TTS, bez dodatkowych fade’ów
            isCapturingCommand = true
            speak(result.reply, keepListeningAfter: true, faster: true)
        } else {
            isCapturingCommand = false
            fadeSiriGlow(to: 0, duration: 0.45)
            speak(result.reply, keepListeningAfter: false)
            if result.didApplySideEffect {
                hideAvatarTask?.cancel()
                hideAvatarTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                        isAvatarVisible = false
                    }
                    fadeSiriGlow(to: 0, duration: 0.35)
                }
            }
        }
    }

    private func fadeSiriGlow(to value: CGFloat, duration: Double) {
        siriGlowTask?.cancel()
        siriGlowTask = nil
        withAnimation(.easeInOut(duration: duration)) {
            siriGlowIntensity = value
        }
    }

    // MARK: - TTS / audio

    private func speak(_ text: String, keepListeningAfter: Bool, faster: Bool = false) {
        keepListeningAfterSpeech = keepListeningAfter
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pl-PL")
        let base = AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = faster ? base * 1.08 : base * 0.98

        if settings?.autoMuteEnabled == true {
            music?.duckForAssistant(true, autoMuteEnabled: true)
        }

        state = .speaking
        synthesizer.speak(utterance)
    }

    private func restorePlaybackSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { /* ignore */ }
    }

    private func stripWakeWord(from text: String) -> String {
        var result = text
        let lower = text.lowercased()
        for phrase in wakePhrases.sorted(by: { $0.count > $1.count }) {
            if let range = lower.range(of: phrase) {
                let start = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
                let end = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                result.removeSubrange(start..<end)
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func containsWakeWord(_ text: String) -> Bool {
        let lower = text.lowercased()
        return wakePhrases.contains { lower.contains($0) }
    }
}

extension DriveMateAssistant: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            music?.duckForAssistant(false, autoMuteEnabled: settings?.autoMuteEnabled ?? true)
            if keepListeningAfterSpeech {
                keepListeningAfterSpeech = false
                activateListening()
            } else {
                state = .idle
                isCapturingCommand = false
                scheduleHideAvatar()
                resumeWakeIfNeeded()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            music?.duckForAssistant(false, autoMuteEnabled: settings?.autoMuteEnabled ?? true)
            keepListeningAfterSpeech = false
            if state == .speaking { state = .idle }
            isCapturingCommand = false
            resumeWakeIfNeeded()
        }
    }
}
