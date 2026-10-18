import Foundation
import Combine
import SwiftUI

/// Mostek: komendy głosowe → stan UI w `DriveView` (AR, kompas, recenter) + serwisy.
@MainActor
final class DriveVoiceUIBridge: ObservableObject {
    static let shared = DriveVoiceUIBridge()

    enum UICommand: Equatable {
        case recenter
        case setAR(Bool)
        case setCompass(Bool)
    }

    weak var camera: CameraRecorderService?
    weak var settings: AppSettings?
    weak var music: MusicPlayerService?

    @Published private(set) var uiCommandToken = UUID()
    private(set) var lastUICommand: UICommand?

    private init() {}

    func bind(
        camera: CameraRecorderService,
        settings: AppSettings,
        music: MusicPlayerService
    ) {
        self.camera = camera
        self.settings = settings
        self.music = music
    }

    func request(_ command: UICommand) {
        lastUICommand = command
        uiCommandToken = UUID()
    }

    func consumeUICommand() -> UICommand? {
        let command = lastUICommand
        lastUICommand = nil
        return command
    }

    // MARK: - Volume (0…1)

    @discardableResult
    func setVolume(_ value: Double) -> String {
        guard let settings else { return "Nie mogę zmienić głośności." }
        let clamped = min(1, max(0, value))
        settings.musicVolume = clamped
        music?.volume = Float(clamped)
        let pct = Int((clamped * 100).rounded())
        return "Głośność ustawiona na \(pct) procent."
    }

    @discardableResult
    func adjustVolume(by delta: Double) -> String {
        let current = settings?.musicVolume ?? Double(music?.volume ?? 0.75)
        return setVolume(current + delta)
    }

    // MARK: - Recording

    @discardableResult
    func setRecording(enabled: Bool) async -> String {
        guard let settings else { return "Nie mogę sterować nagrywaniem." }
        guard settings.recorderEnabled else {
            return "Nagrywanie jest wyłączone w Ustawieniach. Włącz je tam najpierw."
        }
        guard let camera else { return "Kamera nie jest gotowa." }

        if enabled {
            if camera.isContinuousRecording {
                return "Nagrywanie już jest włączone."
            }
            await camera.requestAccessAndConfigure()
            guard camera.permissionGranted else {
                return camera.lastError ?? "Brak dostępu do kamery."
            }
            camera.startContinuousRecording(clipDuration: 10)
            return "Włączam nagrywanie."
        } else {
            if !camera.isContinuousRecording {
                return "Nagrywanie już jest wyłączone."
            }
            camera.stopContinuousRecording()
            return "Wyłączam nagrywanie."
        }
    }

    // MARK: - Travel mode

    @discardableResult
    func setTravelMode(_ mode: TravelMode) -> String {
        guard let settings else { return "Nie mogę zmienić trybu." }
        if settings.travelMode == mode {
            return "\(mode.title) jest już aktywny."
        }
        settings.travelMode = mode
        return "Przełączam na \(mode.title.lowercased())."
    }
}
