import Foundation
import SwiftUI
import Combine

/// Źródło odtwarzania muzyki w Drive Mate.
enum MusicSource: String, CaseIterable, Identifiable {
    case local
    case appleMusic
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Wgraj Muzykę"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    /// Sterowanie głosowe (pauza / next…) — wyłączone dla Spotify (polityka Spotify).
    var supportsVoiceMusicCommands: Bool {
        switch self {
        case .local, .appleMusic: return true
        case .spotify: return false
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("appearance") var appearanceRaw: String = AppAppearance.dark.rawValue {
        didSet { objectWillChange.send() }
    }

    @AppStorage("recorderEnabled") var recorderEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("autoMuteEnabled") var autoMuteEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    /// Gdy włączone — nawigacja zawsze startuje z GPS użytkownika (bez pytania o start).
    @AppStorage("alwaysUseMyLocation") var alwaysUseMyLocation: Bool = false {
        didSet { objectWillChange.send() }
    }

    /// Model auta do szacowania spalania (np. „Toyota Corolla”).
    @AppStorage("carModel") var carModel: String = "" {
        didSet { objectWillChange.send() }
    }

    /// Ręczne spalanie l/100 km. 0 = użyj estymatora z modelu.
    @AppStorage("fuelConsumptionLPer100") var fuelConsumptionLPer100: Double = 0 {
        didSet { objectWillChange.send() }
    }

    @AppStorage("musicVolume") var musicVolume: Double = 0.75 {
        didSet {
            objectWillChange.send()
            volumeDidChange?(musicVolume)
        }
    }

    @AppStorage("musicSource") var musicSourceRaw: String = MusicSource.local.rawValue {
        didSet { objectWillChange.send() }
    }

    var volumeDidChange: ((Double) -> Void)?

    var musicSource: MusicSource {
        get { MusicSource(rawValue: musicSourceRaw) ?? .local }
        set { musicSourceRaw = newValue.rawValue }
    }

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .dark }
        set { appearanceRaw = newValue.rawValue }
    }

    var isDark: Bool { appearance == .dark }

    var resolvedFuelConsumption: Double? {
        let trimmed = carModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || fuelConsumptionLPer100 > 0 else { return nil }
        if fuelConsumptionLPer100 > 0 { return fuelConsumptionLPer100 }
        let est = CarFuelEstimator.litersPer100km(forModel: trimmed)
        return est > 0 ? est : nil
    }

    func saveCarModel(_ model: String, consumptionOverride: Double? = nil) {
        carModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if let consumptionOverride, consumptionOverride > 0 {
            fuelConsumptionLPer100 = consumptionOverride
        } else if !carModel.isEmpty {
            fuelConsumptionLPer100 = CarFuelEstimator.litersPer100km(forModel: carModel)
        }
    }
}
