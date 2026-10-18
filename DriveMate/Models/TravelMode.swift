import Foundation
import MapKit

/// Tryb jazdy ustawiany m.in. tagiem NFC.
enum TravelMode: String, CaseIterable, Identifiable, Equatable {
    case car
    case bike

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: return "Tryb samochodowy"
        case .bike: return "Tryb rowerowy"
        }
    }

    var shortTitle: String {
        switch self {
        case .car: return "Samochód"
        case .bike: return "Rower"
        }
    }

    var systemImage: String {
        switch self {
        case .car: return "car.fill"
        case .bike: return "bicycle"
        }
    }

    /// Plik Rive (bez rozszerzenia) — fullscreen intro trybu.
    var riveFileName: String {
        switch self {
        case .car: return "mode_car"
        case .bike: return "mode_bike"
        }
    }

    var riveArtboardName: String {
        switch self {
        case .car: return "ModeCar"
        case .bike: return "ModeBike"
        }
    }

    var riveStateMachineName: String { "State Machine 1" }

    /// MapKit: rower → trasy piesze/ścieżki (najbliższy odpowiednik roweru w MKDirections).
    var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .car: return .automobile
        case .bike: return .walking
        }
    }

    var routeLabel: String {
        switch self {
        case .car: return "Trasa samochodowa"
        case .bike: return "Trasa rowerowa"
        }
    }

    /// URI zapisywane na tagu NDEF.
    var nfcURI: URL {
        URL(string: "drivemate://mode/\(rawValue)")!
    }

    static func from(nfcURL url: URL) -> TravelMode? {
        guard url.scheme?.lowercased() == "drivemate" else { return nil }
        let host = url.host?.lowercased()
        if host == "mode" {
            let mode = url.pathComponents.dropFirst().first?.lowercased()
            return TravelMode(rawValue: mode ?? "")
        }
        return TravelMode(rawValue: host ?? "")
    }
}
