import Foundation
import Speech
import AVFoundation
import Combine

/// Rozpoznawanie mowy po polsku (ASR) — buffer → transkrypt dla komend głosowych.
@MainActor
final class PolishSpeechRecognizer: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var isAuthorized = false
    /// 0…1 — głośność wejścia (do wizualizacji fal).
    @Published private(set) var audioLevel: CGFloat = 0

    private let recognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "pl-PL"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "pl"))
            ?? SFSpeechRecognizer()
    }()

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var lastLevelPublish: TimeInterval = 0

    enum ListenMode {
        /// Pełna komenda — cisza kończy i wysyła transkrypt.
        case command
        /// Ciche nasłuchiwanie „Hey Drive” — cisza / koniec sesji → restart.
        case wakeSpot
    }

    /// Wywołane gdy uznamy komendę za zakończoną (cisza / final).
    var onFinalTranscript: ((String) -> Void)?
    /// Każda aktualizacja częściowa (do UI / glow).
    var onPartialTranscript: ((String) -> Void)?
    /// Aktualizacja poziomu audio (0…1).
    var onAudioLevel: ((CGFloat) -> Void)?
    /// Wake-spot: sesja wygasła bez użytecznego tekstu — uruchom ponownie.
    var onWakeSpotNeedsRestart: (() -> Void)?

    private(set) var listenMode: ListenMode = .command

    var localeIdentifier: String {
        recognizer?.locale.identifier ?? "pl-PL"
    }

    var supportsOnDevice: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Permissions

    func preparePermissions() async -> Bool {
        let mic = await requestMic()
        guard mic else {
            status = .unavailable("Brak zgody na mikrofon.")
            isAuthorized = false
            return false
        }
        let speech = await requestSpeech()
        guard speech == .authorized else {
            status = .unavailable("Brak zgody na rozpoznawanie mowy.")
            isAuthorized = false
            return false
        }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Rozpoznawanie mowy niedostępne.")
            isAuthorized = false
            return false
        }
        isAuthorized = true
        return true
    }

    // MARK: - Start / Stop

    func start(mode: ListenMode = .command) async {
        stopEngine()
        listenMode = mode
        status = .preparing
        guard await preparePermissions() else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            if mode == .wakeSpot {
                // Nie dumpuje muzyki — ciche nasłuchiwanie wake word.
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP]
                )
            } else {
                try session.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP]
                )
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = .unavailable("Audio: \(error.localizedDescription)")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device gdy dostępne — niższy latency / prywatność; inaczej sieć.
        req.requiresOnDeviceRecognition = supportsOnDevice
        req.taskHint = mode == .wakeSpot ? .search : .dictation
        if #available(iOS 16.0, *) {
            req.addsPunctuation = false
        }
        request = req

        let input = audioEngine.inputNode
        let hw = input.inputFormat(forBus: 0)
        let format = hw.sampleRate > 0 ? hw : input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .unavailable("Mikrofon niedostępny.")
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.measureLevel(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            status = .unavailable("Nie uruchomiono mikrofonu: \(error.localizedDescription)")
            return
        }

        partialTranscript = ""
        status = .listening
        armSilenceTimer()

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error)
            }
        }
    }

    func stop(submit: Bool) {
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopEngine()
        status = .idle
        audioLevel = 0
        onAudioLevel?(0)
        if submit, text.count >= 2 {
            onFinalTranscript?(text)
        }
    }

    func cancel() {
        stopEngine()
        partialTranscript = ""
        status = .idle
        audioLevel = 0
        onAudioLevel?(0)
    }

    // MARK: - Internals

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard status == .listening else { return }

        if let result {
            let text = result.bestTranscription.formattedString
            if text != partialTranscript {
                partialTranscript = text
                onPartialTranscript?(text)
                armSilenceTimer()
            }
            if result.isFinal {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finishWithCurrentTranscript()
                } else if listenMode == .wakeSpot {
                    requestWakeRestart()
                }
                return
            }
        }

        if let error {
            let ns = error as NSError
            // Brak mowy / timeout — nie gaś, jeśli pusty; wyślij jeśli jest tekst.
            if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 || ns.code == 1101 {
                if !partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finishWithCurrentTranscript()
                } else if listenMode == .wakeSpot {
                    requestWakeRestart()
                } else {
                    armSilenceTimer()
                }
            } else if !partialTranscript.isEmpty {
                finishWithCurrentTranscript()
            } else if listenMode == .wakeSpot {
                requestWakeRestart()
            }
        }
    }

    private func finishWithCurrentTranscript() {
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopEngine()
        status = .idle
        audioLevel = 0
        onAudioLevel?(0)
        guard text.count >= 2 else {
            if listenMode == .wakeSpot { onWakeSpotNeedsRestart?() }
            return
        }
        onFinalTranscript?(text)
    }

    private func requestWakeRestart() {
        stopEngine()
        status = .idle
        audioLevel = 0
        onAudioLevel?(0)
        onWakeSpotNeedsRestart?()
    }

    private func measureLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0
        let strideN = max(frameCount / 256, 1)
        var i = 0
        while i < frameCount {
            let s = channel[i]
            sum += s * s
            i += strideN
        }
        let samples = Float(frameCount / strideN)
        let rms = sqrt(sum / max(samples, 1))
        // Typowy mik. speech ~0.01–0.2; mapuj do 0…1 z lekkim boostem.
        let normalized = min(max(CGFloat(rms) * 8.5, 0), 1)

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelPublish > 0.05 else { return }
        lastLevelPublish = now

        Task { @MainActor [weak self] in
            guard let self, self.status == .listening else { return }
            // Lekkie wygładzenie
            let smoothed = self.audioLevel * 0.45 + normalized * 0.55
            self.audioLevel = smoothed
            self.onAudioLevel?(smoothed)
        }
    }

    private func armSilenceTimer() {
        silenceTask?.cancel()
        let delay: UInt64 = listenMode == .wakeSpot ? 2_800_000_000 : 2_200_000_000
        silenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, status == .listening else { return }
            let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 2 {
                finishWithCurrentTranscript()
            } else if listenMode == .wakeSpot {
                requestWakeRestart()
            }
        }
    }

    private func stopEngine() {
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    private func requestSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
    }
}
