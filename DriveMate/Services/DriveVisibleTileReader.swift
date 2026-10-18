import Foundation
import CoreLocation

/// Zbiera tekst z aktualnie widocznego kafelka / oferty / skrętu do przeczytania na głos.
@MainActor
enum DriveVisibleTileReader {

    struct Snapshot {
        let speechText: String
        /// Czy trzeba przedłużyć widoczność kafelka (info card).
        let holdsInfoCard: Bool
    }

    /// Priorytet: arrival → oferta miejsca → karta info → kafelek skrętu → prędkość/zegar.
    static func currentSnapshot() -> Snapshot? {
        if ArrivalConfirmService.shared.isActive {
            return Snapshot(
                speechText: ArrivalConfirmService.shared.confirmationPrompt(),
                holdsInfoCard: false
            )
        }

        if RestaurantOfferService.shared.isActive, let offer = RestaurantOfferService.shared.offer {
            let parts: [String?] = [
                "Restauracja \(offer.name).",
                offer.address.isEmpty ? nil : offer.address + ".",
                "Odległość \(offer.distanceLabel).",
                "Możesz zatwierdzić albo anulować."
            ]
            return Snapshot(speechText: join(parts), holdsInfoCard: false)
        }

        if StoreOfferService.shared.isActive, let offer = StoreOfferService.shared.offer {
            let parts: [String?] = [
                "\(offer.brandLabel): \(offer.name).",
                offer.address.isEmpty ? nil : offer.address + ".",
                "Odległość \(offer.distanceLabel).",
                "Możesz zatwierdzić albo anulować."
            ]
            return Snapshot(speechText: join(parts), holdsInfoCard: false)
        }

        if GasStationOfferService.shared.isActive, let offer = GasStationOfferService.shared.offer {
            let kind = offer.preferCheapestContext ? "Stacja paliw pod kątem ceny" : "Stacja paliw"
            var parts: [String?] = [
                "\(kind): \(offer.name).",
                offer.address.isEmpty ? nil : offer.address + ".",
                "Odległość \(offer.distanceLabel)."
            ]
            let summary = GasStationOfferService.shared.nearbySummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                parts.append(summary)
            }
            parts.append("Możesz zatwierdzić albo anulować.")
            return Snapshot(speechText: join(parts), holdsInfoCard: false)
        }

        if let card = DriveInfoCardStore.shared.card {
            return Snapshot(speechText: card.speechText, holdsInfoCard: true)
        }

        if let guidance = MapKitNavigationService.shared.mapState?.nextTurnGuidance,
           guidance.showsTurnTile {
            let dist = guidance.isImminent
                ? "teraz"
                : "za \(guidance.distanceLabel.replacingOccurrences(of: " m", with: " metrów").replacingOccurrences(of: " km", with: " kilometrów"))"
            var text = "Skręt \(guidance.direction.spoken) \(dist)."
            let instruction = guidance.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !instruction.isEmpty, instruction.count < 120 {
                text += " \(instruction)."
            }
            return Snapshot(speechText: text, holdsInfoCard: false)
        }

        // Fallback: widoczne kafelki chrome podczas jazdy.
        if MapKitNavigationService.shared.mapState?.isNavigating == true {
            var parts: [String] = []
            let chrome = DriveChromeVisibilityStore.shared
            if chrome.isVisible(.speedometer) {
                let kmh = MapKitNavigationService.shared.location?.speedKmh ?? 0
                parts.append("Prędkość \(kmh) kilometrów na godzinę.")
            }
            if chrome.isVisible(.clock) {
                let f = DateFormatter()
                f.locale = Locale(identifier: "pl_PL")
                f.dateFormat = "H:mm"
                parts.append("Jest godzina \(f.string(from: Date())).")
            }
            if !parts.isEmpty {
                return Snapshot(speechText: parts.joined(separator: " "), holdsInfoCard: false)
            }
        }

        return nil
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.joined(separator: " ")
    }
}

extension DriveInfoCard {
    var speechText: String {
        switch self {
        case let .street(title, body, _):
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if b.isEmpty { return t.isEmpty ? "Kafelek ulicy." : t + "." }
            return "\(t). \(b)"

        case let .fuelCost(distanceKm, liters, costPLN, carModel, consumption):
            return [
                "Paliwo na trasie.",
                String(format: "Dystans %.1f kilometra.", distanceKm),
                String(format: "Zużycie dla auta \(carModel): %.1f litra, czyli %.1f litra na sto kilometrów.", liters, consumption),
                String(format: "Szacowany koszt %.0f złotych.", costPLN)
            ].joined(separator: " ")

        case let .fuelGauge(levelPercent, liters, tankCapacity, rangeKm, carModel, costToFill):
            var lines = [
                "Stan paliwa.",
                "\(Int((levelPercent * 100).rounded())) procent.",
                String(format: "W baku %.1f z %.0f litrów.", liters, tankCapacity),
                String(format: "Zasięg około %.0f kilometrów.", rangeKm),
                "Auto: \(carModel)."
            ]
            if costToFill > 0.5 {
                lines.append(String(format: "Do pełnego baku około %.0f złotych.", costToFill))
            }
            return lines.joined(separator: " ")

        case let .capabilities(items):
            if items.isEmpty { return "Lista umiejętności jest pusta." }
            return "Oto co umiem. " + items.joined(separator: ". ") + "."

        case let .puzzle(category, prompt):
            return "Łamigówka \(category). \(prompt)"
        }
    }
}
