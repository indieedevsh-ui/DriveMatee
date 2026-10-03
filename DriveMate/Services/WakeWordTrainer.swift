import Foundation
import Speech
import AVFoundation
import Combine

/// Trening wymowy „Hey Drive” — 3 próbki przez AVAudioEngine + SFSpeechRecognizer.
@MainActor
final class WakeWordTrainer: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case ready
        case recording(sampleIndex: Int) // 0…2
        case processing(sampleIndex: Int)
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var samples: [String] = []
    @Published private(set) var lastHeard: String = ""
    @Published private(set) var audioLevel: CGFloat = 0
    @Published private(set) var hint: String = ""

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var sampleGeneration = 0
    private var speechDetectedInSample = false
    private var peakLevelInSample: CGFloat = 0

    /// en-US lepiej łapie „Hey Drive”; pl-PL — fonetyczne „hej drajw”.
    private lazy var recognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "pl-PL"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "pl"))
            ?? SFSpeechRecognizer()
    }()

    var progressLabel: String {
        if !hint.isEmpty { return hint }
        switch phase {
        case .idle, .ready:
            return "Powtórz „Hey Drive” trzy razy."
        case .recording(let i):
            return "Próbka \(i + 1) z 3 — powiedz teraz: Hey Drive"
        case .processing(let i):
            return "Próbka \(i + 1) zapisana…"
        case .completed:
            return "Gotowe — Drive Mate nauczył się Twojej wymowy."
        case .failed(let msg):
            return msg
        }
    }

    var sampleCount: Int { samples.count }

    func reset() {
        stopEngine(endRequest: true)
        samples = []
        lastHeard = ""
        audioLevel = 0
        hint = ""
        speechDetectedInSample = false
        peakLevelInSample = 0
        phase = .ready
    }

    func startTraining() {
        samples = []
        lastHeard = ""
        hint = "Przygotowuję mikrofon…"
        phase = .ready
        // Zwolnij mic z asystenta / wake — inaczej trening nie dostaje audio.
        NotificationCenter.default.post(name: .driveMateWakeTrainingWillStart, object: nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            beginSample(index: 0)
        }
    }

    func cancel() {
        stopEngine(endRequest: true)
        phase = .idle
        audioLevel = 0
        hint = ""
        NotificationCenter.default.post(name: .driveMateWakeTrainingDidEnd, object: nil)
    }

    private func beginSample(index: Int) {
        guard index < 3 else {
            finishTraining()
            return
        }
        sampleGeneration += 1
        let gen = sampleGeneration
        speechDetectedInSample = false
        peakLevelInSample = 0
        lastHeard = ""
        hint = ""
        phase = .recording(sampleIndex: index)
        Task { await startListening(sampleIndex: index, generation: gen) }
    }

    private func startListening(sampleIndex: Int, generation: Int) async {
        stopEngine(endRequest: true)
        guard generation == sampleGeneration else { return }

        guard await ensurePermissions() else {
            phase = .failed("Brak zgody na mikrofon lub rozpoznawanie mowy.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            phase = .failed("Rozpoznawanie mowy niedostępne (sprawdź sieć / Siri).")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.setPreferredSampleRate(48_000)
            try? session.setPreferredIOBufferDuration(0.01)
        } catch {
            phase = .failed("Audio: \(error.localizedDescription)")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        req.taskHint = .dictation
        req.contextualStrings = [
            "Hey Drive", "Hey Drive Mate", "Hej Drive", "Hej Drive Mate",
            "Hey Dryve", "Hej Drajw", "Drive Mate", "OK Drive", "Ej Drive"
        ]
        if #available(iOS 16.0, *) {
            req.addsPunctuation = false
        }
        request = req

        let input = audioEngine.inputNode
        // Krytyczne: format sprzętowy wejścia — inaczej tap jest cichy / ASR milczy.
        let hw = input.inputFormat(forBus: 0)
        let format = hw.sampleRate > 0 && hw.channelCount > 0
            ? hw
            : input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .failed("Mikrofon niedostępny.")
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.measureLevel(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            phase = .failed("Nie uruchomiono mikrofonu: \(error.localizedDescription)")
            return
        }

        hint = "Słucham — powiedz „Hey Drive”"
        armWatchdog(sampleIndex: sampleIndex, generation: generation)

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleResult(
                    result,
                    error: error,
                    sampleIndex: sampleIndex,
                    generation: generation
                )
            }
        }
    }

    private func handleResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        sampleIndex: Int,
        generation: Int
    ) {
        guard generation == sampleGeneration else { return }
        guard case .recording(let idx) = phase, idx == sampleIndex else { return }

        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lastHeard = text
                hint = "Słyszę: „\(text)”"
                speechDetectedInSample = true
                armSilenceCommit(sampleIndex: sampleIndex, generation: generation)

                // Natychmiast gdy widać wariant wake — nie czekaj na final.
                if Self.looksLikeWake(text), text.count >= 3 {
                    // Krótka pauza na dokończenie frazy
                    armSilenceCommit(sampleIndex: sampleIndex, generation: generation, delayNs: 700_000_000)
                }
            }
            if result.isFinal, text.count >= 2 {
                commitSample(text, index: sampleIndex, generation: generation)
                return
            }
        }

        if let error {
            let ns = error as NSError
            // Timeout / no speech — jeśli coś już usłyszeliśmy, zapisz.
            if !lastHeard.isEmpty {
                commitSample(lastHeard, index: sampleIndex, generation: generation)
            } else if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 || ns.code == 1101 {
                hint = "Nie złapałem mowy — powiedz głośniej „Hey Drive”."
                // Restart tej samej próbki
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard generation == self.sampleGeneration else { return }
                    guard case .recording = self.phase else { return }
                    await self.startListening(sampleIndex: sampleIndex, generation: generation)
                }
            }
        }
    }

    private func armSilenceCommit(
        sampleIndex: Int,
        generation: Int,
        delayNs: UInt64 = 1_250_000_000
    ) {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            guard generation == sampleGeneration else { return }
            guard case .recording(let idx) = phase, idx == sampleIndex else { return }
            let text = lastHeard.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 2 {
                commitSample(text, index: sampleIndex, generation: generation)
            }
        }
    }

    /// Jeśli przez dłuższy czas jest dźwięk, ale brak tekstu — ponów sesję ASR.
    private func armWatchdog(sampleIndex: Int, generation: Int) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            guard generation == sampleGeneration else { return }
            guard case .recording(let idx) = phase, idx == sampleIndex else { return }
            if !lastHeard.isEmpty {
                commitSample(lastHeard, index: sampleIndex, generation: generation)
                return
            }
            if peakLevelInSample > 0.12 {
                hint = "Słyszę dźwięk, ale nie tekst — ponawiam nasłuch…"
                await startListening(sampleIndex: sampleIndex, generation: generation)
            } else {
                hint = "Nic nie słychać — sprawdź mikrofon i powiedz „Hey Drive”."
                await startListening(sampleIndex: sampleIndex, generation: generation)
            }
        }
    }

    private func commitSample(_ text: String, index: Int, generation: Int) {
        guard generation == sampleGeneration else { return }
        guard case .recording(let idx) = phase, idx == index else { return }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else { return }

        phase = .processing(sampleIndex: index)
        stopEngine(endRequest: true)
        silenceTask?.cancel()
        watchdogTask?.cancel()

        samples.append(cleaned)
        lastHeard = cleaned
        hint = "Zapisano: „\(cleaned)”"

        if samples.count >= 3 {
            finishTraining()
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard generation == self.sampleGeneration else { return }
                beginSample(index: samples.count)
            }
        }
    }

    private func finishTraining() {
        stopEngine(endRequest: true)
        guard samples.count >= 3 else {
            phase = .failed("Potrzeba 3 próbek. Spróbuj ponownie.")
            NotificationCenter.default.post(name: .driveMateWakeTrainingDidEnd, object: nil)
            return
        }
        DriveMateMemoryStore.shared.saveWakeTraining(samples: Array(samples.prefix(3)))
        phase = .completed
        audioLevel = 0
        hint = ""
        NotificationCenter.default.post(name: .driveMateWakeTrainingDidEnd, object: nil)
    }

    private static func looksLikeWake(_ text: String) -> Bool {
        let n = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
        let keys = [
            "hey drive", "hej drive", "hei drive", "hey drajw", "hej drajw",
            "drive mate", "drajw", "drive", "hey", "hej"
        ]
        return keys.contains { n.contains($0) }
    }

    private func measureLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        let step = max(n / 128, 1)
        var i = 0
        while i < n {
            let s = channel[i]
            sum += s * s
            i += step
        }
        let rms = sqrt(sum / Float(max(n / step, 1)))
        let level = min(max(CGFloat(rms) * 10, 0), 1)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioLevel = self.audioLevel * 0.4 + level * 0.6
            if level > self.peakLevelInSample {
                self.peakLevelInSample = level
            }
            if level > 0.14 {
                self.speechDetectedInSample = true
            }
        }
    }

    private func stopEngine(endRequest: Bool) {
        silenceTask?.cancel()
        silenceTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        if endRequest {
            request?.endAudio()
        }
        request = nil
        task?.cancel()
        task = nil
    }

    private func ensurePermissions() async -> Bool {
        let mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard mic else { return false }
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        return speech == .authorized
    }
}

extension Notification.Name {
    static let driveMateWakeTrainingWillStart = Notification.Name("driveMateWakeTrainingWillStart")
    static let driveMateWakeTrainingDidEnd = Notification.Name("driveMateWakeTrainingDidEnd")
}
