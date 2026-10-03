import Foundation
import MapKit
import CoreLocation
import FoundationModels

struct ParkingOption: Identifiable, Equatable {
    let id: UUID
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    let isFree: Bool
    /// 0 = darmowy, 1 = tani, 2 = średni, 3 = droższy (heurystyka / AI).
    let costTier: Int
    let costHint: String
    let reason: String

    var distanceLabel: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters.rounded())) m"
    }

    static func == (lhs: ParkingOption, rhs: ParkingOption) -> Bool {
        lhs.id == rhs.id
    }
}

/// Szuka parkingów przez Apple Maps: najpierw darmowe ≤1 km, potem dalsze darmowe + bliższe płatne (od najtańszych).
@MainActor
final class ParkingSearchService {
    static let shared = ParkingSearchService()

    private let freeKeywords = [
        "darmow", "bezpłatn", "bezplatn", "free parking", "park and ride", "p+r", "p & r",
        "bez opłat", "bez oplat", "gratis"
    ]
    private let paidKeywords = [
        "płatn", "platn", "paid", "parking fee", "garaż", "garaz", "parking house",
        "underground", "strefa płatnego", "strefa platnego", "parkometr"
    ]
    private let cheapHints = ["p+r", "park and ride", "uliczny", "street", "niski", "tani"]
    private let expensiveHints = ["centrum", "center", "underground", "garaż", "garaz", "hotel", "airport", "lotnisk"]

    func findNearbyParking(near coordinate: CLLocationCoordinate2D) async throws -> [ParkingOption] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // 1) Parkingi w ~1 km
        let near1km = await searchParking(near: coordinate, radiusMeters: 1_200, queries: [
            "parking", "parking samochodowy", "parking darmowy", "parking bezpłatny"
        ])

        var freeNear = classifyAndFilter(near1km, origin: origin, preferFree: true)
            .filter { $0.isFree && $0.distanceMeters <= 1_000 }

        if !freeNear.isEmpty {
            freeNear.sort { $0.distanceMeters < $1.distanceMeters }
            let final = Array(await enrichWithAI(freeNear, origin: coordinate).prefix(6))
            MapComplianceStore.shared.showPlaces(
                title: "Parkingi darmowe (Apple Maps)",
                pins: final.map { ($0.coordinate, $0.name) },
                center: coordinate,
                spanMeters: 1_800
            )
            return final
        }

        // 2) Brak darmowych w 1 km → dalsze darmowe + bliższe płatne
        let wider = await searchParking(near: coordinate, radiusMeters: 5_000, queries: [
            "parking", "parking darmowy", "parking bezpłatny", "P+R", "parking płatny", "garaż parkingowy"
        ])
        let all = classifyAndFilter(wider, origin: origin, preferFree: false)

        let freeFar = all
            .filter { $0.isFree }
            .sorted { $0.distanceMeters < $1.distanceMeters }

        let paidNear = all
            .filter { !$0.isFree && $0.distanceMeters <= 2_500 }
            .sorted {
                if $0.costTier != $1.costTier { return $0.costTier < $1.costTier }
                return $0.distanceMeters < $1.distanceMeters
            }

        var combined: [ParkingOption] = []
        combined.append(contentsOf: freeFar.prefix(4))
        combined.append(contentsOf: paidNear.prefix(4))

        // Dedup by coordinate
        var seen = Set<String>()
        combined = combined.filter { opt in
            let key = String(format: "%.4f,%.4f", opt.coordinate.latitude, opt.coordinate.longitude)
            return seen.insert(key).inserted
        }

        if combined.isEmpty {
            // Fallback: dowolne parkingi w okolicy
            combined = classifyAndFilter(near1km + wider, origin: origin, preferFree: false)
                .sorted { $0.distanceMeters < $1.distanceMeters }
        }

        let final = Array(await enrichWithAI(combined, origin: coordinate).prefix(8))
        if !final.isEmpty {
            MapComplianceStore.shared.showPlaces(
                title: "Parkingi (Apple Maps)",
                pins: final.map { ($0.coordinate, $0.name) },
                center: coordinate,
                spanMeters: 2_800
            )
        }
        return final
    }

    // MARK: - Search

    private func searchParking(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        queries: [String]
    ) async -> [MKMapItem] {
        var items: [MKMapItem] = []
        var seen = Set<String>()

        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest]
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.parking])
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: radiusMeters * 2,
                longitudinalMeters: radiusMeters * 2
            )

            do {
                let response = try await MKLocalSearch(request: request).start()
                for item in response.mapItems {
                    let c = item.location.coordinate
                    let key = String(format: "%.5f,%.5f-%@", c.latitude, c.longitude, item.name ?? "")
                    if seen.insert(key).inserted {
                        items.append(item)
                    }
                }
            } catch {
                continue
            }
        }

        // Dodatkowe wyszukiwanie bez filtra POI (czasem lepiej łapie P+R / nazwy lokalne)
        let loose = MKLocalSearch.Request()
        loose.naturalLanguageQuery = "parking"
        loose.resultTypes = [.pointOfInterest, .address]
        loose.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        if let response = try? await MKLocalSearch(request: loose).start() {
            for item in response.mapItems {
                let name = (item.name ?? "").lowercased()
                let isParking = item.pointOfInterestCategory == .parking
                    || name.contains("parking")
                    || name.contains("p+r")
                    || name.contains("garaż")
                    || name.contains("garaz")
                guard isParking else { continue }
                let c = item.location.coordinate
                let key = String(format: "%.5f,%.5f-%@", c.latitude, c.longitude, item.name ?? "")
                if seen.insert(key).inserted {
                    items.append(item)
                }
            }
        }

        return items
    }

    private func classifyAndFilter(
        _ items: [MKMapItem],
        origin: CLLocation,
        preferFree: Bool
    ) -> [ParkingOption] {
        items.compactMap { item -> ParkingOption? in
            let coord = item.location.coordinate
            guard abs(coord.latitude) > 0.0001 || abs(coord.longitude) > 0.0001 else { return nil }
            let distance = origin.distance(
                from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            )
            let blob = [
                item.name,
                item.placemark.title,
                item.placemark.thoroughfare,
                item.pointOfInterestCategory?.rawValue
            ].compactMap { $0 }.joined(separator: " ").lowercased()

            let isFree = classifyFree(blob)
            let tier = estimateCostTier(blob: blob, isFree: isFree)
            let address = [
                item.placemark.thoroughfare,
                item.placemark.subThoroughfare,
                item.placemark.locality
            ].compactMap { $0 }.joined(separator: " ")

            return ParkingOption(
                id: UUID(),
                name: item.name ?? "Parking",
                address: address.isEmpty ? (item.placemark.title ?? "") : address,
                coordinate: coord,
                distanceMeters: distance,
                isFree: isFree,
                costTier: tier,
                costHint: isFree ? "Darmowy" : costHint(for: tier),
                reason: isFree
                    ? (distance <= 1_000 ? "Darmowy w pobliżu" : "Darmowy dalej")
                    : "Płatny · \(costHint(for: tier).lowercased())"
            )
        }
        .sorted { a, b in
            if preferFree {
                if a.isFree != b.isFree { return a.isFree && !b.isFree }
            }
            if a.costTier != b.costTier { return a.costTier < b.costTier }
            return a.distanceMeters < b.distanceMeters
        }
    }

    private func classifyFree(_ blob: String) -> Bool {
        if freeKeywords.contains(where: { blob.contains($0) }) { return true }
        if paidKeywords.contains(where: { blob.contains($0) }) { return false }
        // Domyślnie nieznany → traktuj jako płatny (ostrożniej), chyba że P+R
        if blob.contains("p+r") || blob.contains("park and ride") { return true }
        return false
    }

    private func estimateCostTier(blob: String, isFree: Bool) -> Int {
        if isFree { return 0 }
        if expensiveHints.contains(where: { blob.contains($0) }) { return 3 }
        if cheapHints.contains(where: { blob.contains($0) }) { return 1 }
        return 2
    }

    private func costHint(for tier: Int) -> String {
        switch tier {
        case 0: return "Darmowy"
        case 1: return "Raczej tani"
        case 3: return "Raczej droższy"
        default: return "Średni koszt"
        }
    }

    // MARK: - AI ranking

    private func enrichWithAI(
        _ options: [ParkingOption],
        origin: CLLocationCoordinate2D
    ) async -> [ParkingOption] {
        guard !options.isEmpty else { return options }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return options }

        let list = options.enumerated().map { idx, o in
            "\(idx + 1). \(o.name) | \(o.address) | \(o.distanceLabel) | hint: \(o.costHint) | free=\(o.isFree)"
        }.joined(separator: "\n")

        let session = LanguageModelSession(
            model: model,
            instructions: """
                Jesteś asystentem parkingowym Drive Mate.
                Oceń parkingi z Apple Maps: darmowy vs płatny oraz względny koszt.
                Odpowiedz TYLKO liniami: INDEX|free_or_paid|TIER|krótki_powód
                INDEX od 1. free_or_paid = free albo paid. TIER: 0=free, 1=tani, 2=średni, 3=drogi.
                Powód po polsku, max 6 słów.
                """
        )

        do {
            let prompt = """
                Lokalizacja kierowcy: \(origin.latitude), \(origin.longitude)
                Parkingi z mapy:
                \(list)

                Priorytet: darmowe najbliższe; jeśli brak w 1 km — darmowe dalsze + bliższe płatne od najtańszych.
                """
            let response = try await session.respond(to: prompt)
            return applyAIRanking(response.content, to: options)
        } catch {
            return options
        }
    }

    private func applyAIRanking(_ text: String, to options: [ParkingOption]) -> [ParkingOption] {
        var updated = options
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count >= 3,
                  let index = Int(parts[0]),
                  index >= 1, index <= updated.count else { continue }

            let kind = parts[1].lowercased()
            let isFree = kind.contains("free") || kind.contains("darm")
            let tierToken = parts.count >= 3 ? parts[2] : "2"
            let parsedTier = Int(tierToken.filter(\.isNumber)) ?? (isFree ? 0 : 2)
            let tier = isFree ? 0 : min(3, max(1, parsedTier))
            let reason = parts.count >= 4 ? parts[3] : updated[index - 1].reason
            let old = updated[index - 1]
            updated[index - 1] = ParkingOption(
                id: old.id,
                name: old.name,
                address: old.address,
                coordinate: old.coordinate,
                distanceMeters: old.distanceMeters,
                isFree: isFree,
                costTier: tier,
                costHint: isFree ? "Darmowy" : costHint(for: tier),
                reason: reason
            )
        }

        return updated.sorted {
            if $0.isFree != $1.isFree { return $0.isFree && !$1.isFree }
            if $0.costTier != $1.costTier { return $0.costTier < $1.costTier }
            return $0.distanceMeters < $1.distanceMeters
        }
    }
}
