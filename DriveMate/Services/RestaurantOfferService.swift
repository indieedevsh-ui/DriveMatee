import Foundation
import CoreLocation
import Combine
import MapKit
import UIKit

/// Przerwana trasa (np. zjazd do restauracji podczas nawigacji).
struct InterruptedRoute: Equatable, Codable {
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var shortLabel: String {
        if title.count <= 28 { return title }
        return String(title.prefix(26)) + "…"
    }
}

@MainActor
final class InterruptedRouteStore: ObservableObject {
    static let shared = InterruptedRouteStore()

    @Published private(set) var route: InterruptedRoute?

    private let key = "interruptedRoute.v1"

    init() { load() }

    func save(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        route = InterruptedRoute(
            title: title,
            subtitle: subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        persist()
    }

    func clear() {
        route = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(InterruptedRoute.self, from: data) else {
            route = nil
            return
        }
        route = decoded
    }

    private func persist() {
        guard let route,
              let data = try? JSONEncoder().encode(route) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct RestaurantOffer: Equatable {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    var snapshotImage: UIImage?

    var distanceLabel: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters.rounded())) m"
    }

    static func == (lhs: RestaurantOffer, rhs: RestaurantOffer) -> Bool {
        lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Oferta restauracji + dwuetapowe potwierdzenie (UI / głos).
@MainActor
final class RestaurantOfferService: ObservableObject {
    static let shared = RestaurantOfferService()

    enum Phase: Equatable {
        case idle
        case offering
        case awaitingVoiceConfirm
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var offer: RestaurantOffer?
    @Published private(set) var isSearching = false

    /// True gdy trasa do restauracji zastępuje aktywną nawigację.
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
        near coordinate: CLLocationCoordinate2D,
        interruptingActiveRoute: Bool
    ) async -> String {
        isSearching = true
        willInterruptActiveRoute = interruptingActiveRoute
        defer { isSearching = false }

        do {
            guard let found = try await MapKitNavigationService.shared.findNearestRestaurant(near: coordinate) else {
                dismiss()
                return "Nie znalazłem restauracji w okolicy."
            }
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let dist = origin.distance(
                from: CLLocation(latitude: found.place.latitude, longitude: found.place.longitude)
            )
            let snapshot = await Self.makeSnapshot(
                coordinate: CLLocationCoordinate2D(latitude: found.place.latitude, longitude: found.place.longitude),
                title: found.place.name
            )
            offer = RestaurantOffer(
                name: found.place.name,
                address: found.place.address,
                coordinate: CLLocationCoordinate2D(latitude: found.place.latitude, longitude: found.place.longitude),
                distanceMeters: dist,
                snapshotImage: snapshot
            )
            phase = .offering
            // Mała mapa Apple przy ofercie (compliance)
            MapComplianceStore.shared.showPlace(
                name: found.place.name,
                coordinate: CLLocationCoordinate2D(latitude: found.place.latitude, longitude: found.place.longitude),
                spanMeters: 900
            )
            return "Znalazłem \(found.place.name) w odległości \(RestaurantOffer(name: found.place.name, address: found.place.address, coordinate: CLLocationCoordinate2D(latitude: found.place.latitude, longitude: found.place.longitude), distanceMeters: dist, snapshotImage: nil).distanceLabel). Potwierdź lub anuluj."
        } catch {
            dismiss()
            return "Nie udało się wyszukać restauracji."
        }
    }

    /// Po zatwierdzeniu (przycisk / głos) — pytanie AI.
    func confirmationPrompt() -> String {
        guard let offer else { return "Czy chcesz wybrać to miejsce?" }
        return "Czy chcesz jechać do \(offer.name)?"
    }

    func navigateToOfferIfConfirmed() async -> (reply: String, started: Bool) {
        guard let offer else {
            dismiss()
            return ("Brak wybranej restauracji.", false)
        }

        // Zapisz przerwaną trasę jeśli była aktywna nawigacja
        if willInterruptActiveRoute,
           let mapState = MapKitNavigationService.shared.mapState,
           mapState.isNavigating,
           let dest = mapState.destinationCoordinate,
           let title = mapState.destinationTitle {
            InterruptedRouteStore.shared.save(
                title: title,
                subtitle: mapState.statusBanner ?? "",
                coordinate: dest
            )
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
            return ("Nie udało się wyznaczyć trasy do restauracji.", false)
        }
    }

    private static func makeSnapshot(
        coordinate: CLLocationCoordinate2D,
        title: String
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        options.size = CGSize(width: 640, height: 320)
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snap = try await snapshotter.start()
            let image = snap.image
            let renderer = UIGraphicsImageRenderer(size: image.size)
            return renderer.image { _ in
                image.draw(at: .zero)
                let point = snap.point(for: coordinate)
                let pin = UIImage(systemName: "fork.knife.circle.fill")?
                    .withTintColor(DriveMatePalette.limeRouteUI, renderingMode: .alwaysOriginal)
                let size: CGFloat = 36
                pin?.draw(in: CGRect(
                    x: point.x - size / 2,
                    y: point.y - size,
                    width: size,
                    height: size
                ))
                _ = title
            }
        } catch {
            return nil
        }
    }
}
