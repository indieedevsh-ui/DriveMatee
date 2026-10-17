import Foundation
import CoreLocation
import Combine
import UIKit
import MapKit

/// Karty informacyjne Drive Mate (ulica / koszt paliwa / umiejętności).
enum DriveInfoCard: Equatable {
    case street(title: String, body: String, image: UIImage?)
    case fuelCost(
        distanceKm: Double,
        liters: Double,
        costPLN: Double,
        carModel: String,
        consumptionLPer100: Double
    )
    /// Wskaźnik baku — poziom, litry, zasięg i koszt do pełnego.
    case fuelGauge(
        levelPercent: Double,
        liters: Double,
        tankCapacity: Double,
        rangeKm: Double,
        carModel: String,
        costToFillPLN: Double
    )
    /// Lista umiejętności — zamyka się po 10 s albo po „Zamknij”.
    case capabilities(items: [String])

    /// Karty zamykane po TTS + 1.5 s (nie dotyczy okienka umiejętności).
    var autoDismissesAfterSpeech: Bool {
        switch self {
        case .capabilities: return false
        default: return true
        }
    }

    var autoDismisses: Bool { autoDismissesAfterSpeech }

    static func == (lhs: DriveInfoCard, rhs: DriveInfoCard) -> Bool {
        switch (lhs, rhs) {
        case let (.street(t1, b1, _), .street(t2, b2, _)):
            return t1 == t2 && b1 == b2
        case let (.fuelCost(d1, l1, c1, m1, _), .fuelCost(d2, l2, c2, m2, _)):
            return d1 == d2 && l1 == l2 && c1 == c2 && m1 == m2
        case let (.fuelGauge(p1, l1, t1, r1, _, _), .fuelGauge(p2, l2, t2, r2, _, _)):
            return p1 == p2 && l1 == l2 && t1 == t2 && r1 == r2
        case let (.capabilities(a), .capabilities(b)):
            return a == b
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

    var isCapabilitiesCardActive: Bool {
        if case .capabilities = card { return true }
        return false
    }

    func present(_ card: DriveInfoCard) {
        dismissTask?.cancel()
        withAnimationOptional {
            self.card = card
        }
        // Okienko umiejętności: stałe 10 s, niezależnie od TTS.
        if case .capabilities = card {
            scheduleTimedDismiss(afterSeconds: 10)
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

    /// Wywołaj po zakończeniu TTS — zamyka kartę po 1.5 s (nie umiejętności).
    func scheduleDismissAfterSpeech(delaySeconds: Double = 1.5) {
        guard let card, card.autoDismissesAfterSpeech else { return }
        scheduleTimedDismiss(afterSeconds: delaySeconds)
    }

    private func scheduleTimedDismiss(afterSeconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    private func withAnimationOptional(_ body: () -> Void) {
        body()
    }
}
