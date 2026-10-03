import Foundation
import Combine

/// Kafelki UI nawigacji, które Drive Mate może ukryć / pokazać głosem.
/// Wyłączone z mechaniki: zakończ trasę, panel muzyki, kafelek skrętu.
enum DriveChromeTile: String, CaseIterable, Identifiable, Codable {
    case speedometer
    case clock
    case driveButton
    case recenter
    case recording

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speedometer: return "prędkościomierz"
        case .clock: return "zegar"
        case .driveButton: return "Drive"
        case .recenter: return "wyśrodkuj"
        case .recording: return "nagrywanie"
        }
    }

    /// Dopasowanie z komendy głosowej / tekstu.
    static func resolve(fromQuery query: String) -> DriveChromeTile? {
        let q = query.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))

        if q.contains("predkosciomierz") || q.contains("predkosc") || q.contains("speed")
            || q.contains("km/h") || q.contains("kmh") || q.contains("speedo") {
            return .speedometer
        }
        if q.contains("zegar") || q.contains("godzin") || q.contains("czas") || q.contains("clock") {
            return .clock
        }
        if q.contains("nagr") || q.contains("recording") || q.contains("rec ") || q == "rec" {
            return .recording
        }
        if q.contains("wysrodk") || q.contains("recenter") || q.contains("centruj")
            || q.contains("lokalizacj") && q.contains("przycisk") {
            return .recenter
        }
        if q.contains("drive") || q.contains("drajw") || q.contains("kompozytor")
            || q.contains("wpisz") || q.contains("panel drive") {
            return .driveButton
        }
        // „kafelek x” — sama nazwa
        for tile in Self.allCases {
            if q == tile.rawValue || q.contains(tile.displayName) {
                return tile
            }
        }
        return nil
    }
}

@MainActor
final class DriveChromeVisibilityStore: ObservableObject {
    static let shared = DriveChromeVisibilityStore()

    @Published private(set) var hidden: Set<DriveChromeTile> = []

    private let key = "driveMate.chrome.hidden.v1"

    private init() { load() }

    func isVisible(_ tile: DriveChromeTile) -> Bool {
        !hidden.contains(tile)
    }

    @discardableResult
    func setVisible(_ tile: DriveChromeTile, visible: Bool) -> String {
        if visible {
            hidden.remove(tile)
        } else {
            hidden.insert(tile)
        }
        persist()
        objectWillChange.send()
        let name = tile.displayName
        return visible ? "Pokazuję \(name)." : "Ukrywam \(name)."
    }

    func showAll() {
        hidden.removeAll()
        persist()
        objectWillChange.send()
    }

    private func load() {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else { return }
        hidden = Set(raw.compactMap { DriveChromeTile(rawValue: $0) })
    }

    private func persist() {
        UserDefaults.standard.set(hidden.map(\.rawValue), forKey: key)
    }
}
