import Foundation
import CoreLocation
import Combine
import MapKit
import UIKit

struct StoreOffer: Equatable {
    let name: String
    let address: String
    let brandLabel: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    var snapshotImage: UIImage?

    var distanceLabel: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters.rounded())) m"
    }

    static func == (lhs: StoreOffer, rhs: StoreOffer) -> Bool {
        lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Najbliższy sklep (Żabka, Lewiatan, Empik, Sinsay…) + potwierdzenie UI/głos.
@MainActor
final class StoreOfferService: ObservableObject {
    static let shared = StoreOfferService()

    enum Phase: Equatable {
        case idle
        case offering
        case awaitingVoiceConfirm
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var offer: StoreOffer?
    @Published private(set) var isSearching = false

    private(set) var willInterruptActiveRoute = false

    var isActive: Bool { phase != .idle && offer != nil }

    func dismiss() {
        phase = .idle
        offer = nil
        isSearching = false
        willInterruptActiveRoute = false
    }

    func beginAwaitingVoiceConfirm() {
        guard offer != nil else { return }
        phase = .awaitingVoiceConfirm
    }

    func findAndPresentNearest(
        brandQuery: String,
        brandLabel: String,
        near coordinate: CLLocationCoordinate2D,
        interruptingActiveRoute: Bool
    ) async -> String {
        isSearching = true
        willInterruptActiveRoute = interruptingActiveRoute
        defer { isSearching = false }

        do {
            guard let found = try await MapKitNavigationService.shared.findNearestStore(
                query: brandQuery,
                near: coordinate
            ) else {
                dismiss()
                return "Nie znalazłem \(brandLabel) w okolicy."
            }
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let dest = CLLocation(latitude: found.place.latitude, longitude: found.place.longitude)
            let dist = origin.distance(from: dest)
            let photo = await AppleMapsPlaceVisuals.placePhoto(
                at: CLLocationCoordinate2D(latitude: found.place.latitude, longitude: found.place.longitude)
            )
            let coord = CLLocationCoordinate2D(latitude: found.place.latitude, longitude: found.place.longitude)
            offer = StoreOffer(
                name: found.place.name,
                address: found.place.address,
                brandLabel: brandLabel,
                coordinate: coord,
                distanceMeters: dist,
                snapshotImage: photo
            )
            phase = .offering
            let label = StoreOffer(
                name: found.place.name,
                address: found.place.address,
                brandLabel: brandLabel,
                coordinate: coord,
                distanceMeters: dist,
                snapshotImage: nil
            ).distanceLabel
            return "Znalazłem \(found.place.name) — \(label). Powiedz tak / jedź albo anuluj."
        } catch {
            dismiss()
            return "Nie udało się wyszukać sklepu."
        }
    }

    func confirmationPrompt() -> String {
        guard let offer else { return "Czy chcesz jechać do tego sklepu?" }
        return "Czy chcesz jechać do \(offer.name)?"
    }

    func navigateToOfferIfConfirmed() async -> (reply: String, started: Bool) {
        guard let offer else {
            dismiss()
            return ("Brak wybranego sklepu.", false)
        }
        if willInterruptActiveRoute {
            InterruptedRouteStore.shared.snapshotActiveNavigationIfNeeded()
        }
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
            MapComplianceStore.shared.clear()
            return ("Startuję nawigację do \(name).", true)
        } catch NavigationError.disclaimerRequired {
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return ("Zaakceptuj warunki nawigacji, potem potwierdź ponownie.", false)
        } catch {
            return ("Nie udało się wyznaczyć trasy do sklepu.", false)
        }
    }
}
