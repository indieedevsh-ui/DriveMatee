import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case drive
    case recorder
    case stats
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: "DRIVE MATE"
        case .recorder: "RECORDER"
        case .stats: "STATS"
        case .settings: "SETTINGS"
        }
    }

    /// Zakładki widoczne w danym trybie jazdy (rower: Stats zamiast Recorder).
    static func visibleTabs(for mode: TravelMode) -> [AppTab] {
        switch mode {
        case .car: return [.drive, .recorder, .settings]
        case .bike: return [.drive, .stats, .settings]
        }
    }
}
