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
    /// Auto-wyłączenie gdy kierowca milczy podczas aktywnego słuchania.
    private var listeningIdleTask: Task<Void, Never>?
    private var keepListeningAfterSpeech = false
    /// Włączone przez cały czas sekcji Drive (idle + nawigacja).
    private var navigationWakeEnabled = false
    /// Pełne przechwytywanie komendy (po wake / przycisku) — nie restartuj wake.
    private var isCapturingCommand = false
    /// Chroni przed podwójnym triggereem wake (partial + final).
    private var wakeTriggerLocked = false
    /// Trening Hey Drive przejmuje mikrofon.
    private var wakePausedForTraining = false

    /// 3 s bez żadnej mowy po aktywacji → koniec.
    private let listeningIdleTimeoutNs: UInt64 = 3_000_000_000
    /// Max długość jednej sesji dyktafonu (zabezpieczenie przed nieskończonym nasłuchem).
    private let maxCaptureNs: UInt64 = 7_500_000_000
    private var maxCaptureTask: Task<Void, Never>?

    private weak var settings: AppSettings?
    private weak var music: MusicPlayerService?

    private let wakePhrases = [
        "hey drive mate", "hej drive mate", "hey drivemate", "hej drivemate",
        "hey drive", "hei drive", "hej drive", "ej drive", "ok drive",
        "hej drajw", "hey drajw", "hei drajw", "hej draj", "hey draj", "ej drajw",
        "hey dryve", "hej dryve", "hey draif", "hej draif", "hey draiw", "hej draiw",
        "drive mate", "drivemate", "drajw mate", "hej drajwmejt", "hey drajwmejt",
        "a drive", "aj drive", "a drajw", "ok drajw"
    ]

    override init() {
        super.init()
        synthesizer.delegate = self
        wireASR()
        wireTrainingNotifications()
    }

    private func wireTrainingNotifications() {
        NotificationCenter.default.addObserver(
            forName: .driveMateWakeTrainingWillStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseCaptureForWakeTraining()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .driveMateWakeTrainingDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeCaptureAfterWakeTraining()
            }
        }
    }

    private func pauseCaptureForWakeTraining() {
        wakePausedForTraining = true
        wakeRestartTask?.cancel()
        listeningIdleTask?.cancel()
        maxCaptureTask?.cancel()
        isWakeListening = false
        isCapturingCommand = false
        wakeTriggerLocked = true
        asr.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        audioLevel = 0
        if state == .listening || state == .speaking {
            state = .idle
        }
        fadeSiriGlow(to: 0, duration: 0.25)
    }

    private func resumeCaptureAfterWakeTraining() {
        wakeTriggerLocked = false
        wakePausedForTraining = false
        restorePlaybackSession()
        if navigationWakeEnabled {
            scheduleWakeSpotting(after: 0.45)
        }
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

    /// Włącz / wyłącz ciągłe nasłuchiwanie „Hey Drive” w sekcji Drive (idle + nawigacja).
    func setNavigationWakeListening(_ enabled: Bool) {
        navigationWakeEnabled = enabled
        if enabled {
            if wakePausedForTraining { return }
            Task { _ = await asr.preparePermissions() }
            scheduleWakeSpotting(after: 0.2)
        } else {
            wakeRestartTask?.cancel()
            isWakeListening = false
            wakeTriggerLocked = false
            if !isCapturingCommand {
                asr.cancel()
                if state == .listening { state = .idle }
                fadeSiriGlow(to: 0, duration: 0.35)
            }
        }
    }

    func dismissAvatar() {
        listeningIdleTask?.cancel()
        hideAvatarTask?.cancel()
        speechGlowTask?.cancel()
        withAnimation(.easeOut(duration: 0.35)) { speechGlow = 0 }
        fadeSiriGlow(to: 0, duration: 0.45)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
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

    /// Natychmiastowe zamknięcie aktywnego asystenta (np. „anuluj nasłuchiwanie”).
    func cancelActiveListening(spokenReply: String? = nil) {
        listeningIdleTask?.cancel()
        maxCaptureTask?.cancel()
        keepListeningAfterSpeech = false
        isCapturingCommand = false
        isWakeListening = false
        wakeTriggerLocked = false
        asr.cancel()
        audioLevel = 0
        synthesizer.stopSpeaking(at: .immediate)
        if let spokenReply, !spokenReply.isEmpty {
            reply = spokenReply
            speak(spokenReply, keepListeningAfter: false, faster: true)
        } else {
            reply = ""
            state = .idle
            fadeSiriGlow(to: 0, duration: 0.45)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                isAvatarVisible = false
            }
            restorePlaybackSession()
            resumeWakeIfNeeded()
        }
    }

    func toggleListening() {
        if !isAvatarVisible {
            activateListening()
            return
        }
        if state == .listening, !isWakeListening {
            let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            listeningIdleTask?.cancel()
            maxCaptureTask?.cancel()
            if hasText {
                asr.stop(submit: true)
            } else {
                endListeningWithoutCommand(spoken: "Anulowano.")
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

            // Wake: aktywuj NATYCHMIAST na partialu.
            if self.isWakeListening, !self.isCapturingCommand, !self.wakeTriggerLocked {
                if self.containsWakeWord(text) {
                    self.handleWakeSpottingTranscript(text, fromPartial: true)
                    return
                }
            }

            // Dyktafon: każde nowe słowo odświeża timer ciszy (koniec wypowiedzi).
            if self.isCapturingCommand, !self.isWakeListening {
                self.resetListeningIdleTimer()
                self.pulseSpeechGlow()
            }
        }
        asr.onFinalTranscript = { [weak self] text in
            guard let self else { return }
            // Komenda dyktafonu — zawsze przetwarzaj (nawet gdy wakeTriggerLocked).
            if self.isCapturingCommand, !self.isWakeListening {
                self.finishDictation(with: text)
                return
            }
            if self.isWakeListening, !self.isCapturingCommand {
                self.handleWakeSpottingTranscript(text, fromPartial: false)
                return
            }
        }
        asr.onAudioLevel = { [weak self] level in
            guard let self else { return }
            if self.isWakeListening { return }
            if abs(level - self.audioLevel) > 0.04 {
                self.audioLevel = level
            }
        }
        asr.onWakeSpotNeedsRestart = { [weak self] in
            guard let self else { return }
            guard !self.wakeTriggerLocked, !self.isCapturingCommand else { return }
            self.isWakeListening = false
            if self.state == .listening { self.state = .idle }
            self.scheduleWakeSpotting(after: 0.2)
        }
    }

    /// Koniec nagrania dyktafonu → analiza → działanie (albo krótka odmowa).
    private func finishDictation(with raw: String) {
        guard isCapturingCommand, !isWakeListening else { return }
        listeningIdleTask?.cancel()
        maxCaptureTask?.cancel()
        listeningIdleTask = nil
        maxCaptureTask = nil

        // Zatrzymaj mic zanim zaczniemy myśleć / mówić.
        asr.cancel()
        audioLevel = 0
        isCapturingCommand = false

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = trimmed

        music?.duckForAssistant(false, autoMuteEnabled: settings?.autoMuteEnabled ?? true)
        restorePlaybackSession()

        let hasWake = containsWakeWord(trimmed)
        let stripped = stripWakeWord(from: trimmed)
        let command = hasWake ? stripped : trimmed

        guard !command.isEmpty else {
            if hasWake {
                activateListening()
            } else {
                endListeningWithoutCommand(spoken: "Nie usłyszałem. Powiedz Hey Drive i spróbuj ponownie.")
            }
            return
        }

        Task { await handleCommand(command) }
    }

    private func handleWakeSpottingTranscript(_ text: String, fromPartial: Bool) {
        let hasWake = containsWakeWord(text)
        let stripped = stripWakeWord(from: text)

        guard hasWake else {
            if !fromPartial {
                isWakeListening = false
                scheduleWakeSpotting(after: 0.15)
            }
            return
        }

        guard !wakeTriggerLocked else { return }
        wakeTriggerLocked = true
        isWakeListening = false
        wakeRestartTask?.cancel()

        if stripped.isEmpty {
            activateListening()
        } else {
            // „Hey Drive jedź na Wawel” — od razu komenda, bez drugiej sesji.
            music?.duckForAssistant(false, autoMuteEnabled: settings?.autoMuteEnabled ?? true)
            restorePlaybackSession()
            asr.cancel()
            showAvatar()
            fadeSiriGlow(to: 1, duration: 0.22)
            isCapturingCommand = false
            Task { await handleCommand(stripped) }
        }
    }

    private func scheduleWakeSpotting(after delay: TimeInterval) {
        wakeRestartTask?.cancel()
        guard navigationWakeEnabled else { return }
        guard !wakePausedForTraining else { return }
        wakeRestartTask = Task { @MainActor in
            let ns = UInt64(max(delay, 0) * 1_000_000_000)
            if ns > 0 {
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            startWakeSpottingIfNeeded()
        }
    }

    private func startWakeSpottingIfNeeded() {
        guard navigationWakeEnabled else { return }
        guard !wakePausedForTraining else { return }
        guard !isCapturingCommand else { return }
        guard !isWakeListening else { return }
        guard !wakeTriggerLocked || state == .idle else { return }
        switch state {
        case .thinking, .speaking: return
        case .listening where isCapturingCommand: return
        case .unavailable: return
        default: break
        }

        wakeTriggerLocked = false
        isWakeListening = true
        isCapturingCommand = false
        state = .listening
        transcript = ""
        fadeSiriGlow(to: 0, duration: 0.15)

        Task {
            await asr.start(mode: .wakeSpot)
            if case .unavailable = asr.status {
                isWakeListening = false
                state = .idle
                scheduleWakeSpotting(after: 1.5)
            }
        }
    }

    private func resumeWakeIfNeeded() {
        guard navigationWakeEnabled else { return }
        wakeTriggerLocked = false
        scheduleWakeSpotting(after: 0.25)
    }

    private func activateListening() {
        wakeRestartTask?.cancel()
        hideAvatarTask?.cancel()
        listeningIdleTask?.cancel()
        maxCaptureTask?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        keepListeningAfterSpeech = false
        isWakeListening = false
        wakeTriggerLocked = true
        isCapturingCommand = true
        asr.cancel()
        showAvatar()
        reply = "Słucham…"
        transcript = ""
        audioLevel = 0
        state = .listening
        fadeSiriGlow(to: 1, duration: 0.22)

        if settings?.autoMuteEnabled == true {
            music?.duckForAssistant(true, autoMuteEnabled: true)
        }

        // Brak mowy w ogóle → zamknij.
        resetListeningIdleTimer()
        // Twardy limit sesji dyktafonu.
        armMaxCaptureTimer()

        Task {
            await asr.start(mode: .command)
            guard state == .listening, isCapturingCommand else { return }
            if case .unavailable(let msg) = asr.status {
                lastError = msg
                endListeningWithoutCommand(spoken: "Mikrofon niedostępny.")
            }
        }
    }

    private func armMaxCaptureTimer() {
        maxCaptureTask?.cancel()
        maxCaptureTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: maxCaptureNs)
            guard !Task.isCancelled else { return }
            guard isCapturingCommand, !isWakeListening, state == .listening else { return }
            // Wymuś koniec — weź co jest w partialu.
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 2 {
                asr.stop(submit: true)
            } else {
                endListeningWithoutCommand(spoken: "Nie usłyszałem komendy.")
            }
        }
    }

    private func resetListeningIdleTimer() {
        listeningIdleTask?.cancel()
        guard isCapturingCommand, !isWakeListening, state == .listening else { return }
        listeningIdleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: listeningIdleTimeoutNs)
            guard !Task.isCancelled else { return }
            guard isCapturingCommand, !isWakeListening, state == .listening else { return }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 2 {
                // Była mowa, a potem cisza — wyślij jak dyktafon.
                asr.stop(submit: true)
            } else {
                endListeningWithoutCommand(spoken: "Nie usłyszałem. Powiedz Hey Drive i spróbuj ponownie.")
            }
        }
    }

    private func endListeningWithoutCommand(spoken: String) {
        listeningIdleTask?.cancel()
        maxCaptureTask?.cancel()
        asr.cancel()
        audioLevel = 0
        isCapturingCommand = false
        wakeTriggerLocked = false
        state = .idle
        reply = spoken
        fadeSiriGlow(to: 0.35, duration: 0.35)
        speak(spoken, keepListeningAfter: false, faster: true)
        restorePlaybackSession()
    }

    private func showAvatar() {
        hideAvatarTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            isAvatarVisible = true
        }
    }

    private func scheduleHideAvatar() {
        hideAvatarTask?.cancel()
        listeningIdleTask?.cancel()
        fadeSiriGlow(to: 0, duration: 0.5)
        hideAvatarTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, state == .idle else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
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
            endListeningWithoutCommand(spoken: "Nie usłyszałem komendy.")
            return
        }

        listeningIdleTask?.cancel()
        maxCaptureTask?.cancel()
        wakeRestartTask?.cancel()
        isWakeListening = false
        isCapturingCommand = false
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

        if result.dismissAssistant {
            cancelActiveListening(spokenReply: result.reply.isEmpty ? "OK, wyłączam." : result.reply)
            return
        }

        if result.awaitFurtherInput {
            isCapturingCommand = true
            speak(result.reply, keepListeningAfter: true, faster: true)
        } else {
            isCapturingCommand = false
            wakeTriggerLocked = false
            fadeSiriGlow(to: 0.55, duration: 0.35)
            speak(result.reply, keepListeningAfter: false)
            if result.didApplySideEffect {
                hideAvatarTask?.cancel()
                hideAvatarTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    fadeSiriGlow(to: 0, duration: 0.4)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                        isAvatarVisible = false
                    }
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

    private func containsWakeWord(_ text: String) -> Bool {
        let lower = normalizeWakeText(text)
        let learned = DriveMateMemoryStore.shared.learnedWakePhrases
        if learned.contains(where: { phrase in
            let n = normalizeWakeText(phrase)
            // Wytrenowana fraza — także częściowe dopasowanie (≥4 znaki)
            return !n.isEmpty && (
                lower.contains(n)
                    || (n.count >= 4 && lower.count >= 4 && (n.contains(lower) || lower.contains(n)))
            )
        }) {
            return true
        }
        if wakePhrases.contains(where: { lower.contains(normalizeWakeText($0)) }) {
            return true
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"(hej|hey|hei|ej|ok|a|aj)\s*(drajw|draj|draif|draiw|dryve|drive|drivemate|drajwmejt)"#,
            options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        if regex.firstMatch(in: lower, options: [], range: range) != nil {
            return true
        }
        return lower.contains("drive mate")
            || lower.contains("drivemate")
            || lower.contains("drajw mate")
            || lower.contains("drajwmate")
            || lower == "hey drive"
            || lower == "hej drive"
            || lower == "hej drajw"
            || lower == "hey drajw"
    }

    private func stripWakeWord(from text: String) -> String {
        var result = normalizeWakeText(text)
        let allPhrases = DriveMateMemoryStore.shared.learnedWakePhrases + wakePhrases
        for phrase in allPhrases.sorted(by: { $0.count > $1.count }) {
            let needle = normalizeWakeText(phrase)
            if needle.count >= 3, let range = result.range(of: needle) {
                result.removeSubrange(range)
                break
            }
        }
        if let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(hej|hey|hei|ej|ok|a|aj)\s*(drajw|draj|draif|draiw|dryve|drive|drivemate|drajwmejt)\b(\s*mate)?"#,
            options: []
        ) {
            let ns = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: ns.length),
                withTemplate: ""
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalizeWakeText(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension DriveMateAssistant: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            music?.duckForAssistant(false, autoMuteEnabled: settings?.autoMuteEnabled ?? true)
            DriveInfoCardStore.shared.scheduleDismissAfterSpeech(delaySeconds: 1.5)
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
            if DriveInfoCardStore.shared.isActive {
                DriveInfoCardStore.shared.dismiss()
            }
            if state == .speaking { state = .idle }
            isCapturingCommand = false
            resumeWakeIfNeeded()
        }
    }
}
