import Foundation
import CoreLocation
import Combine

/// Pytanie o ukończenie trasy w promieniu 20 m od flagi celu.
@MainActor
final class ArrivalConfirmService: ObservableObject {
    static let shared = ArrivalConfirmService()

    static let arrivalRadiusMeters: CLLocationDistance = 20
    /// Po „nie” — nie pytaj ponownie, dopóki kierowca nie oddali się o tyle metrów.
    private static let rearmDistanceMeters: CLLocationDistance = 60

    @Published private(set) var isPrompting = false
    @Published private(set) var destinationTitle: String?

    private var suppressed = false
    private var activeDestinationKey: String?

    var isActive: Bool { isPrompting }

    func resetForNewTrip() {
        isPrompting = false
        destinationTitle = nil
        suppressed = false
        activeDestinationKey = nil
    }

    func update(
        userCoordinate: CLLocationCoordinate2D?,
        destinationCoordinate: CLLocationCoordinate2D?,
        destinationTitle: String?,
        isNavigating: Bool
    ) {
        guard isNavigating, let userCoordinate, let destinationCoordinate else {
            if !isNavigating { resetForNewTrip() }
            return
        }

        let key = String(format: "%.5f,%.5f", destinationCoordinate.latitude, destinationCoordinate.longitude)
        if activeDestinationKey != key {
            activeDestinationKey = key
            suppressed = false
            isPrompting = false
        }

        let distance = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(
                latitude: destinationCoordinate.latitude,
                longitude: destinationCoordinate.longitude
            ))

        if suppressed {
            if distance > Self.rearmDistanceMeters {
                suppressed = false
            }
            return
        }

        guard distance <= Self.arrivalRadiusMeters else {
            if isPrompting, distance > Self.arrivalRadiusMeters + 15 {
                isPrompting = false
            }
            return
        }

        guard !isPrompting else { return }
        self.destinationTitle = destinationTitle ?? "cel"
        isPrompting = true
    }

    func dismissKeepNavigating() {
        isPrompting = false
        suppressed = true
    }

    func consumePromptForCompletion() {
        isPrompting = false
        suppressed = true
    }

    func confirmationPrompt() -> String {
        let name = destinationTitle ?? "celu"
        return "Jesteś przy \(name). Ukończyć trasę? Powiedz tak albo nie."
    }
}
