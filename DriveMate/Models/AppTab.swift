import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case drive
    case recorder
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: "DRIVE"
        case .recorder: "RECORDER"
        case .settings: "SETTINGS"
        }
    }
}
