import Foundation

/// Tryb wnioskowania asystenta Drive Mate.
enum AssistantInferenceMode: String, CaseIterable, Identifiable {
    case deterministic
    case foundation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deterministic: return "Model deterministyczny"
        case .foundation: return "Foundation Models"
        }
    }

    var subtitle: String {
        switch self {
        case .deterministic:
            return "Offline, wiele kluczy odpowiedzi, łamigówki i ciekawostki bez AI."
        case .foundation:
            return "Apple Intelligence — wymaga iPhone 15 Pro lub nowszego."
        }
    }
}

/// Skuteczny wybór modelu: na urządzeniach poniżej 15 Pro zawsze deterministyczny.
@MainActor
enum AssistantModelPolicy {
    static var preferredModeKey: String { "assistantInferenceMode" }
    static var packInstalledKey: String { "deterministicBrain.installed.v1" }

    static var preferredMode: AssistantInferenceMode {
        let raw = UserDefaults.standard.string(forKey: preferredModeKey) ?? ""
        if let mode = AssistantInferenceMode(rawValue: raw), !raw.isEmpty { return mode }
        return DeviceCapability.supportsFoundationModelsHardware ? .foundation : .deterministic
    }

    /// Na starszych iPhone’ach wymuszamy deterministyczny; na 15 Pro+ — preferencja użytkownika.
    static var effectiveMode: AssistantInferenceMode {
        guard DeviceCapability.supportsFoundationModelsHardware else {
            return .deterministic
        }
        return preferredMode
    }

    static var canChooseFoundation: Bool {
        DeviceCapability.supportsFoundationModelsHardware
    }

    static var usesFoundationModels: Bool {
        effectiveMode == .foundation
    }

    static var usesDeterministic: Bool {
        effectiveMode == .deterministic
    }
}

extension Notification.Name {
    static let assistantInferenceModeDidChange = Notification.Name("assistantInferenceModeDidChange")
    static let deterministicBrainPackDidChange = Notification.Name("deterministicBrainPackDidChange")
}
