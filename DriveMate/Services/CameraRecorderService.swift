import AVFoundation
import Combine
import UIKit

/// Tylna kamera + ciągłe klipy 10 s (bez mikrofonu — zero wpływu na muzykę).
@MainActor
final class CameraRecorderService: NSObject, ObservableObject {
    @Published private(set) var isSessionRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var isContinuousRecording = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var statusMessage: String = "Gotowy do podglądu"
    @Published var lastError: String?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "pl.drivemate.camera")
    private var clipDuration: TimeInterval = 10
    private var isConfigured = false
    private var videoDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private weak var clipStorage: ClipStorageService?
    private var restartTask: Task<Void, Never>?

    var onClipSaved: (() -> Void)?
    var showsRecordingIndicator: Bool { isContinuousRecording }

    func bind(storage: ClipStorageService) {
        clipStorage = storage
    }

    /// Podgląd rejestruje warstwę, by RotationCoordinator dopasował kąt do UI.
    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) {
        if previewLayer === layer { return }
        previewLayer = layer
        rebuildRotationCoordinator()
        applyCurrentRotation()
    }

    func requestAccessAndConfigure() async {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        permissionGranted = video
        guard video else {
            statusMessage = "Brak dostępu do kamery"
            lastError = "Włącz dostęp do kamery w Ustawieniach systemowych."
            return
        }
        if !isConfigured {
            await configureSession()
            isConfigured = true
        }
        startSession()
        applyCurrentRotation()
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            Task { @MainActor in
                self.isSessionRunning = true
                if !self.isContinuousRecording {
                    self.statusMessage = "Podgląd tylnej kamery"
                }
                self.applyCurrentRotation()
            }
        }
    }

    func stopSession() {
        guard !isContinuousRecording else {
            statusMessage = "Nagrywanie w tle…"
            return
        }
        stopRecordingIfNeeded()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    func toggleContinuousRecording(clipDuration: TimeInterval = 10) {
        if isContinuousRecording {
            stopContinuousRecording()
        } else {
            startContinuousRecording(clipDuration: clipDuration)
        }
    }

    func startContinuousRecording(clipDuration: TimeInterval = 10) {
        guard permissionGranted else { return }
        self.clipDuration = clipDuration
        isContinuousRecording = true
        statusMessage = "Nagrywanie ciągłe · \(Int(clipDuration)) s"
        preserveMusicAudioSession()
        configureMaxClipDuration()
        startSession()
        beginNextClip()
    }

    func stopContinuousRecording() {
        isContinuousRecording = false
        restartTask?.cancel()
        restartTask = nil
        stopRecordingIfNeeded()
        statusMessage = "Zatrzymano nagrywanie"
    }

    private func configureMaxClipDuration() {
        // Automatyczne ucięcie po 10 s — pewniejsze niż Timer.
        movieOutput.maxRecordedDuration = CMTime(seconds: clipDuration, preferredTimescale: 600)
        movieOutput.maxRecordedFileSize = 0
    }

    private func beginNextClip() {
        guard isContinuousRecording, permissionGranted else { return }
        guard !movieOutput.isRecording else { return }

        applyCurrentRotation()
        configureMaxClipDuration()
        preserveMusicAudioSession()

        guard movieOutput.connection(with: .video) != nil else {
            lastError = "Wyjście wideo niedostępne"
            isContinuousRecording = false
            return
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString).mp4")
        movieOutput.startRecording(to: temp, recordingDelegate: self)
        isRecording = true
        statusMessage = "Nagrywanie · \(Int(clipDuration)) s"
    }

    func stopRecordingIfNeeded() {
        restartTask?.cancel()
        restartTask = nil
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        isRecording = false
    }

    func applyCurrentRotation() {
        let captureAngle = currentCaptureRotationAngle()
        let previewAngle = currentPreviewRotationAngle()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let connection = self.movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(captureAngle) {
                connection.videoRotationAngle = captureAngle
            }
        }
        if let preview = previewLayer,
           let connection = preview.connection,
           connection.isVideoRotationAngleSupported(previewAngle) {
            connection.videoRotationAngle = previewAngle
        }
    }

    private func currentCaptureRotationAngle() -> CGFloat {
        if let coordinator = rotationCoordinator {
            return coordinator.videoRotationAngleForHorizonLevelCapture
        }
        return Self.fallbackRotationAngle()
    }

    private func currentPreviewRotationAngle() -> CGFloat {
        if let coordinator = rotationCoordinator {
            return coordinator.videoRotationAngleForHorizonLevelPreview
        }
        return Self.fallbackRotationAngle()
    }

    /// Fallback gdy brak RotationCoordinator — Landscape = poziomy kadr.
    static func fallbackRotationAngle() -> CGFloat {
        let orientation: UIInterfaceOrientation = {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.first?.interfaceOrientation ?? .landscapeLeft
        }()
        // Sensor kamery jest w portrait; w landscape trzeba obrócić bufor.
        switch orientation {
        case .landscapeLeft: return 90
        case .landscapeRight: return 270
        case .portrait: return 0
        case .portraitUpsideDown: return 180
        default: return 90
        }
    }

    /// Zachowane dla CameraPreviewView.
    static func rotationAngleForCurrentInterface() -> CGFloat {
        fallbackRotationAngle()
    }

    private func rebuildRotationCoordinator() {
        rotationObservation?.invalidate()
        rotationObservation = nil
        guard let device = videoDevice else {
            rotationCoordinator = nil
            return
        }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.applyCurrentRotation()
            }
        }
    }

    private func preserveMusicAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    }

    private func configureSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.session.beginConfiguration()
                if self.session.canSetSessionPreset(.hd1280x720) {
                    self.session.sessionPreset = .hd1280x720
                } else {
                    self.session.sessionPreset = .medium
                }
                self.session.automaticallyConfiguresApplicationAudioSession = false

                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }

                var device: AVCaptureDevice?
                if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: camera),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    device = camera
                    do {
                        try camera.lockForConfiguration()
                        if camera.isExposureModeSupported(.continuousAutoExposure) {
                            camera.exposureMode = .continuousAutoExposure
                        }
                        if camera.isFocusModeSupported(.continuousAutoFocus) {
                            camera.focusMode = .continuousAutoFocus
                        }
                        camera.unlockForConfiguration()
                    } catch { /* ignore */ }
                }

                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                    self.movieOutput.movieFragmentInterval = .invalid
                    if let connection = self.movieOutput.connection(with: .video),
                       connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .off
                    }
                }

                self.session.commitConfiguration()

                Task { @MainActor in
                    self.videoDevice = device
                    self.rebuildRotationCoordinator()
                    self.applyCurrentRotation()
                }

                continuation.resume()
            }
        }
    }
}

extension CameraRecorderService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            isRecording = false

            let shouldContinue = isContinuousRecording

            if let error {
                let ns = error as NSError
                // maxRecordedDuration kończy z kodem często bez „prawdziwego” błędu treści
                let isMaxDurationStop = ns.domain == AVFoundationErrorDomain
                    && (ns.code == AVError.maximumDurationReached.rawValue
                        || ns.code == AVError.diskFull.rawValue)
                if !isMaxDurationStop, ns.code != AVError.sessionWasInterrupted.rawValue {
                    // Plik mógł być mimo to zapisany — sprawdź rozmiar
                    let size = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    if size < 10_000 {
                        lastError = error.localizedDescription
                        try? FileManager.default.removeItem(at: outputFileURL)
                        if shouldContinue {
                            scheduleNextClip()
                        } else {
                            statusMessage = "Błąd nagrywania"
                        }
                        return
                    }
                }
            }

            // Zapisz klip do biblioteki
            let size = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > 10_000 {
                clipStorage?.addClip(at: outputFileURL, durationSeconds: clipDuration)
                onClipSaved?()
            } else {
                try? FileManager.default.removeItem(at: outputFileURL)
            }

            if shouldContinue {
                statusMessage = "Zapisano · następny klip…"
                scheduleNextClip()
            } else {
                statusMessage = "Zapisano klip"
            }
        }
    }

    @MainActor
    private func scheduleNextClip() {
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, isContinuousRecording else { return }
            beginNextClip()
        }
    }
}
