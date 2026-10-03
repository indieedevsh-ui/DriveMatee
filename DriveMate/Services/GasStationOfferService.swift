import Foundation
import CoreLocation
import Combine
import MapKit
import UIKit

struct GasStationOffer: Equatable {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    var photo: UIImage?
    var preferCheapestContext: Bool

    var distanceLabel: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters.rounded())) m"
    }

    static func == (lhs: GasStationOffer, rhs: GasStationOffer) -> Bool {
        lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

@MainActor
final class GasStationOfferService: ObservableObject {
    static let shared = GasStationOfferService()

    enum Phase: Equatable {
        case idle
        case offering
        case awaitingVoiceConfirm
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var offer: GasStationOffer?
    @Published private(set) var nearbySummary: String = ""

    var isActive: Bool { phase != .idle && offer != nil }

    func dismiss() {
        phase = .idle
        offer = nil
        nearbySummary = ""
    }

    func beginAwaitingVoiceConfirm() {
        guard offer != nil else { return }
        phase = .awaitingVoiceConfirm
    }

    func confirmationPrompt() -> String {
        guard let offer else { return "Czy chcesz jechać na tę stację?" }
        return "Czy chcesz jechać do \(offer.name)?"
    }

    func findAndPresent(
        near coordinate: CLLocationCoordinate2D,
        preferCheapest: Bool,
        interruptingActiveRoute: Bool
    ) async -> String {
        _ = interruptingActiveRoute
        do {
            let stations = try await MapKitNavigationService.shared.findNearbyGasStations(
                near: coordinate,
                limit: preferCheapest ? 5 : 3
            )
            guard let first = stations.first else {
                dismiss()
                return "Nie znalazłem stacji paliw w okolicy."
            }
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let dist = origin.distance(
                from: CLLocation(latitude: first.latitude, longitude: first.longitude)
            )
            let photo = await AppleMapsPlaceVisuals.placePhoto(
                at: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
            )

            if preferCheapest {
                nearbySummary = stations.prefix(3).enumerated().map { idx, place in
                    let d = origin.distance(
                        from: CLLocation(latitude: place.latitude, longitude: place.longitude)
                    )
                    let label = d >= 1000 ? String(format: "%.1f km", d / 1000) : "\(Int(d.rounded())) m"
                    return "\(idx + 1)) \(place.name) (\(label))"
                }.joined(separator: " · ")
            } else {
                nearbySummary = ""
            }

            offer = GasStationOffer(
                name: first.name,
                address: first.address,
                coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                distanceMeters: dist,
                photo: photo,
                preferCheapestContext: preferCheapest
            )
            phase = .offering

            let distLabel = dist >= 1000
                ? String(format: "%.1f km", dist / 1000)
                : "\(Int(dist.rounded())) m"

            if preferCheapest {
                return "Nie mam live cen z Apple Maps. Najbliższe stacje: \(nearbySummary). Proponuję \(first.name) (\(distLabel)). Spoko / tak / jedź — albo anuluj."
            }
            return "Najbliższa stacja: \(first.name), około \(distLabel). Spoko / tak / jedź — albo anuluj."
        } catch {
            dismiss()
            return "Nie udało się wyszukać stacji paliw."
        }
    }

    func navigateToOfferIfConfirmed() async -> (reply: String, started: Bool) {
        guard let offer else {
            dismiss()
            return ("Brak wybranej stacji.", false)
        }
        InterruptedRouteStore.shared.snapshotActiveNavigationIfNeeded()
        do {
            _ = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: offer.coordinate.latitude,
                toLongitude: offer.coordinate.longitude,
                destinationName: offer.name
            )
            NotificationCenter.default.post(
                name: .driveMateDidNavigate,
                object: nil,
                userInfo: [
                    "title": offer.name,
                    "subtitle": offer.address,
                    "lat": offer.coordinate.latitude,
                    "lon": offer.coordinate.longitude,
                    "saveRecent": false
                ]
            )
            let name = offer.name
            dismiss()
            return ("Startuję nawigację do \(name).", true)
        } catch NavigationError.disclaimerRequired {
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return ("Zaakceptuj warunki nawigacji, potem potwierdź ponownie.", false)
        } catch {
            return ("Nie udało się wyznaczyć trasy do stacji.", false)
        }
    }
}
