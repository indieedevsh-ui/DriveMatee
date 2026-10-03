import Foundation
import CoreLocation
import Combine
import UIKit
import MapKit

/// Karty informacyjne Drive Mate (ulica / koszt paliwa) — auto-zamknięcie po TTS + 1.5 s.
enum DriveInfoCard: Equatable {
    case street(title: String, body: String, image: UIImage?)
    case fuelCost(
        distanceKm: Double,
        liters: Double,
        costPLN: Double,
        carModel: String,
        consumptionLPer100: Double
    )

    var autoDismisses: Bool { true }

    static func == (lhs: DriveInfoCard, rhs: DriveInfoCard) -> Bool {
        switch (lhs, rhs) {
        case let (.street(t1, b1, _), .street(t2, b2, _)):
            return t1 == t2 && b1 == b2
        case let (.fuelCost(d1, l1, c1, m1, _), .fuelCost(d2, l2, c2, m2, _)):
            return d1 == d2 && l1 == l2 && c1 == c2 && m1 == m2
        default:
            return false
        }
    }
}

@MainActor
final class DriveInfoCardStore: ObservableObject {
    static let shared = DriveInfoCardStore()

    @Published private(set) var card: DriveInfoCard?
    private var dismissTask: Task<Void, Never>?

    var isActive: Bool { card != nil }

    func present(_ card: DriveInfoCard) {
        dismissTask?.cancel()
        withAnimationOptional {
            self.card = card
        }
    }

    /// Aktualizacja zdjęcia ulicy po asynchronicznym pobraniu (bez zamykania karty).
    func updateStreetImage(_ image: UIImage?) {
        guard case let .street(title, body, _) = card else { return }
        card = .street(title: title, body: body, image: image)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimationOptional {
            card = nil
        }
    }

    /// Wywołaj po zakończeniu TTS — zamyka kartę po 1.5 s.
    func scheduleDismissAfterSpeech(delaySeconds: Double = 1.5) {
        guard let card, card.autoDismisses else { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    private func withAnimationOptional(_ body: () -> Void) {
        body()
    }
}
