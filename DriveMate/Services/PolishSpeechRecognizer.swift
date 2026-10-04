import Foundation
import Speech
import AVFoundation
import Combine

/// Rozpoznawanie mowy (ASR) — komendy + ciche „Hey Drive”.
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
    @Published private(set) var audioLevel: CGFloat = 0

    /// pl-PL do komend; en-US lepiej łapie „Hey Drive”.
    private let plRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "pl-PL"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "pl"))
    }()
    private let enRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    }()

    private var activeRecognizer: SFSpeechRecognizer? {
        listenMode == .wakeSpot
            ? (enRecognizer ?? plRecognizer ?? SFSpeechRecognizer())
            : (plRecognizer ?? enRecognizer ?? SFSpeechRecognizer())
    }

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var sessionWatchdog: Task<Void, Never>?
    private var lastLevelPublish: TimeInterval = 0
    private var permissionsReady = false
    private var startGeneration = 0

    enum ListenMode {
        case command
        case wakeSpot
    }

    var onFinalTranscript: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onAudioLevel: ((CGFloat) -> Void)?
    var onWakeSpotNeedsRestart: (() -> Void)?

    private(set) var listenMode: ListenMode = .command

    var supportsOnDevice: Bool {
        activeRecognizer?.supportsOnDeviceRecognition ?? false
    }

    func preparePermissions() async -> Bool {
        if permissionsReady, isAuthorized { return true }
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
        guard let recognizer = activeRecognizer ?? plRecognizer ?? enRecognizer, recognizer.isAvailable else {
            status = .unavailable("Rozpoznawanie mowy niedostępne.")
            isAuthorized = false
            return false
        }
        isAuthorized = true
        permissionsReady = true
        return true
    }

    func start(mode: ListenMode = .command) async {
        stopEngine(restartWake: false)
        listenMode = mode
        status = .preparing
        startGeneration += 1
        let gen = startGeneration

        guard await preparePermissions() else { return }
        guard gen == startGeneration else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            // spokenAudio działa znacznie lepiej niż measurement dla wake word
            // mixWithOthers — muzyka w aplikacji gra dalej (ściszenie robi MusicPlayerService.duck).
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = .unavailable("Audio: \(error.localizedDescription)")
            return
        }

        guard let recognizer = activeRecognizer, recognizer.isAvailable else {
            status = .unavailable("Rozpoznawanie mowy niedostępne.")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        req.taskHint = mode == .wakeSpot ? .search : .dictation
        if #available(iOS 16.0, *) {
            req.addsPunctuation = false
        }
        var context = [
            "Hey Drive", "Hej Drive", "Hey Drive Mate", "Hej Drive Mate",
            "Drive Mate", "ok Drive", "ej Drive", "Hej Drajw", "Hey Dryve"
        ]
        context.append(contentsOf: DriveMateMemoryStore.shared.learnedWakePhrases)
        req.contextualStrings = Array(Set(context)).prefix(20).map { String($0) }
        request = req

        let input = audioEngine.inputNode
        let hw = input.inputFormat(forBus: 0)
        let format = hw.sampleRate > 0 && hw.channelCount > 0
            ? hw
            : input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .unavailable("Mikrofon niedostępny.")
            return
        }

        input.removeTap(onBus: 0)
        let bufferSize: AVAudioFrameCount = mode == .wakeSpot ? 1024 : 2048
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.measureLevel(from: buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            status = .unavailable("Nie uruchomiono mikrofonu: \(error.localizedDescription)")
            return
        }

        partialTranscript = ""
        status = .listening

        if mode == .wakeSpot {
            // Wake: nie restartuj przy ciszy — dopiero po ~45 s / błędzie.
            armWakeSessionWatchdog(generation: gen)
        }
        // Command: timer ciszy startuje dopiero po pierwszym słowie (jak dyktafon).

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error, generation: gen)
            }
        }
    }

    func stop(submit: Bool) {
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = listenMode
        stopEngine(restartWake: false)
        status = .idle
        audioLevel = 0
        onAudioLevel?(0)
        if submit {
            if text.count >= 2 {
                onFinalTranscript?(text)
            } else if mode == .command {
                onFinalTranscript?("")
            }
        }
    }

    func cancel() {
        stopEngine(restartWake: false)
        partialTranscript = ""
        status = .idle
        audioLevel = 0
        onAudioLevel?(0)
    }

    private func handleRecognition(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        generation: Int
    ) {
        guard generation == startGeneration else { return }
        guard status == .listening else { return }

        if let result {
            let text = result.bestTranscription.formattedString
            if text != partialTranscript {
                partialTranscript = text
                onPartialTranscript?(text)
                if listenMode == .command {
                    armCommandSilenceTimer()
                }
            }
            if result.isFinal {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finishWithCurrentTranscript(allowEmpty: false)
                } else if listenMode == .wakeSpot {
                    requestWakeRestart()
                } else {
                    // Command pusty final — zakończ sesję
                    finishWithCurrentTranscript(allowEmpty: true)
                }
                return
            }
        }

        if let error {
            if !partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finishWithCurrentTranscript(allowEmpty: false)
            } else if listenMode == .wakeSpot {
                requestWakeRestart()
            } else {
                // Brak mowy / timeout — zamknij dyktafon (asystent powie „nie usłyszałem”)
                finishWithCurrentTranscript(allowEmpty: true)
            }
        }
    }

    private func requestWakeRestart() {
        stopEngine(restartWake: false)
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
        let normalized = min(max(CGFloat(rms) * 8.5, 0), 1)

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelPublish > 0.05 else { return }
        lastLevelPublish = now

        Task { @MainActor [weak self] in
            guard let self, self.status == .listening else { return }
            let smoothed = self.audioLevel * 0.45 + normalized * 0.55
            self.audioLevel = smoothed
            self.onAudioLevel?(smoothed)
        }
    }

    private func armCommandSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            // ~0.75 s ciszy po ostatnim słowie = koniec nagrania dyktafonu
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled, status == .listening, listenMode == .command else { return }
            // Zawsze kończ — nawet pusty tekst (asystent zamknie sesję).
            finishWithCurrentTranscript(allowEmpty: true)
        }
    }

    private func armWakeSessionWatchdog(generation: Int) {
        sessionWatchdog?.cancel()
        sessionWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, generation == startGeneration else { return }
            guard status == .listening, listenMode == .wakeSpot else { return }
            if !partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finishWithCurrentTranscript(allowEmpty: false)
            } else {
                requestWakeRestart()
            }
        }
    }

    private func finishWithCurrentTranscript(allowEmpty: Bool = false) {
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopEngine(restartWake: false)
        status = .idle
        audioLevel = 0
        onAudioLevel?(0)
        if text.count >= 2 {
            onFinalTranscript?(text)
        } else if allowEmpty, listenMode == .command {
            onFinalTranscript?("")
        } else if listenMode == .wakeSpot {
            onWakeSpotNeedsRestart?()
        }
    }

    private func stopEngine(restartWake: Bool) {
        silenceTask?.cancel()
        silenceTask = nil
        sessionWatchdog?.cancel()
        sessionWatchdog = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if restartWake { onWakeSpotNeedsRestart?() }
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
