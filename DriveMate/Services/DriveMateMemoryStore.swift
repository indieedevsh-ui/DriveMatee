import Foundation
import CoreLocation
import Combine
import MapKit

// MARK: - Models

struct VisitedPlaceMemory: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var visitedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: visitedAt)
    }
}

/// Preferencja trasy: user unikał wskazanej ulicy ≥3× na tym samym odcinku celu.
struct RouteAvoidanceMemory: Identifiable, Codable, Equatable {
    let id: UUID
    var destinationTitle: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    var avoidedStreetName: String
    var hitCount: Int
    var updatedAt: Date
    /// Próbki GPS z trasy „po swojemu” (uproszczone punkty).
    var preferredPathSamples: [[Double]]

    var isActive: Bool { hitCount >= 3 }

    var preferredCoordinates: [CLLocationCoordinate2D] {
        preferredPathSamples.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }
}

struct WakePronunciationMemory: Codable, Equatable {
    var samples: [String]
    var learnedPhrases: [String]
    var trainedAt: Date?

    static let empty = WakePronunciationMemory(samples: [], learnedPhrases: [], trainedAt: nil)

    var isTrained: Bool { learnedPhrases.count >= 1 && samples.count >= 3 }
}

// MARK: - Store

@MainActor
final class DriveMateMemoryStore: ObservableObject {
    static let shared = DriveMateMemoryStore()

    @Published private(set) var visits: [VisitedPlaceMemory] = []
    @Published private(set) var avoidances: [RouteAvoidanceMemory] = []
    @Published private(set) var wakeProfile: WakePronunciationMemory = .empty

    private let visitsKey = "driveMate.memory.visits.v1"
    private let avoidKey = "driveMate.memory.avoid.v1"
    private let wakeKey = "driveMate.memory.wake.v1"
    private let visitRetentionDays = 3

    /// Aktywna sesja odchylenia od trasy (w trakcie nawigacji).
    private var activeDeviationStreet: String?
    private var activeDeviationSamples: [CLLocationCoordinate2D] = []
    private var consecutiveOffRouteTicks = 0
    private var lastDestKey: String?

    private init() { load() }

    // MARK: - Visits (3 dni)

    func recordVisit(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        pruneVisits()
        visits.removeAll {
            abs($0.latitude - coordinate.latitude) < 0.0002
                && abs($0.longitude - coordinate.longitude) < 0.0002
                && Calendar.current.isDate($0.visitedAt, inSameDayAs: .now)
        }
        visits.insert(
            VisitedPlaceMemory(
                id: UUID(),
                title: cleaned,
                subtitle: subtitle,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                visitedAt: .now
            ),
            at: 0
        )
        persistVisits()
    }

    func removeVisit(id: UUID) {
        visits.removeAll { $0.id == id }
        persistVisits()
    }

    func clearVisits() {
        visits.removeAll()
        persistVisits()
    }

    /// „Tam gdzie byłem N dni temu”.
    func visit(daysAgo: Int) -> VisitedPlaceMemory? {
        pruneVisits()
        let cal = Calendar.current
        guard let target = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return nil }
        let dayVisits = visits.filter { cal.isDate($0.visitedAt, inSameDayAs: target) }
        return dayVisits.first
    }

    func visits(daysAgo: Int) -> [VisitedPlaceMemory] {
        pruneVisits()
        let cal = Calendar.current
        guard let target = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return [] }
        return visits.filter { cal.isDate($0.visitedAt, inSameDayAs: target) }
    }

    private func pruneVisits() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -visitRetentionDays, to: Date()) ?? .distantPast
        let before = visits.count
        visits = visits.filter { $0.visitedAt >= cutoff }
        if visits.count != before { persistVisits() }
    }

    // MARK: - Route avoidance learning

    /// Wołane z GPS podczas nawigacji — uczy uników ulic.
    func observeNavigationAdherence(
        userCoordinate: CLLocationCoordinate2D,
        route: MKRoute?,
        destinationTitle: String?,
        destinationCoordinate: CLLocationCoordinate2D?
    ) {
        guard let route,
              let destinationTitle,
              let destinationCoordinate else {
            resetDeviationSession()
            return
        }

        let dist = Self.distanceToRoute(userCoordinate, route: route)
        if dist > 85 {
            consecutiveOffRouteTicks += 1
            if consecutiveOffRouteTicks == 8 {
                activeDeviationStreet = Self.nearestStepName(to: userCoordinate, route: route)
                    ?? route.name
                    ?? "odcinek trasy"
                activeDeviationSamples = [userCoordinate]
                lastDestKey = destKey(destinationCoordinate)
            } else if consecutiveOffRouteTicks > 8 {
                if let last = activeDeviationSamples.last {
                    if CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
                        .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) > 40 {
                        activeDeviationSamples.append(userCoordinate)
                        if activeDeviationSamples.count > 24 {
                            activeDeviationSamples.removeFirst()
                        }
                    }
                } else {
                    activeDeviationSamples.append(userCoordinate)
                }
            }
        } else if consecutiveOffRouteTicks >= 8 {
            commitDeviationIfNeeded(
                destinationTitle: destinationTitle,
                destinationCoordinate: destinationCoordinate
            )
            resetDeviationSession()
        } else {
            consecutiveOffRouteTicks = 0
        }
    }

    func notifyTripEnded(
        destinationTitle: String?,
        destinationCoordinate: CLLocationCoordinate2D?,
        subtitle: String = ""
    ) {
        if consecutiveOffRouteTicks >= 8,
           let destinationTitle,
           let destinationCoordinate {
            commitDeviationIfNeeded(
                destinationTitle: destinationTitle,
                destinationCoordinate: destinationCoordinate
            )
        }
        resetDeviationSession()
        if let destinationTitle, let destinationCoordinate {
            recordVisit(
                title: destinationTitle,
                subtitle: subtitle,
                coordinate: destinationCoordinate
            )
        }
    }

    private func commitDeviationIfNeeded(
        destinationTitle: String,
        destinationCoordinate: CLLocationCoordinate2D
    ) {
        let street = (activeDeviationStreet ?? "odcinek trasy")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard street.count >= 2 else { return }
        let samples = activeDeviationSamples.prefix(20).map { [$0.latitude, $0.longitude] }

        if let idx = avoidances.firstIndex(where: {
            $0.avoidedStreetName.caseInsensitiveCompare(street) == .orderedSame
                && abs($0.destinationLatitude - destinationCoordinate.latitude) < 0.008
                && abs($0.destinationLongitude - destinationCoordinate.longitude) < 0.008
        }) {
            avoidances[idx].hitCount += 1
            avoidances[idx].updatedAt = .now
            avoidances[idx].destinationTitle = destinationTitle
            if !samples.isEmpty {
                avoidances[idx].preferredPathSamples = Array(samples)
            }
        } else {
            avoidances.insert(
                RouteAvoidanceMemory(
                    id: UUID(),
                    destinationTitle: destinationTitle,
                    destinationLatitude: destinationCoordinate.latitude,
                    destinationLongitude: destinationCoordinate.longitude,
                    avoidedStreetName: street,
                    hitCount: 1,
                    updatedAt: .now,
                    preferredPathSamples: Array(samples)
                ),
                at: 0
            )
        }
        persistAvoidances()
    }

    func removeAvoidance(id: UUID) {
        avoidances.removeAll { $0.id == id }
        persistAvoidances()
    }

    func clearAvoidances() {
        avoidances.removeAll()
        persistAvoidances()
        resetDeviationSession()
    }

    /// Aktywne preferencje (≥3 uniknięcia) blisko celu.
    func activeAvoidances(near destination: CLLocationCoordinate2D) -> [RouteAvoidanceMemory] {
        avoidances.filter {
            $0.isActive
                && abs($0.destinationLatitude - destination.latitude) < 0.012
                && abs($0.destinationLongitude - destination.longitude) < 0.012
        }
    }

    private func resetDeviationSession() {
        consecutiveOffRouteTicks = 0
        activeDeviationStreet = nil
        activeDeviationSamples = []
        lastDestKey = nil
    }

    private func destKey(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.3f,%.3f", c.latitude, c.longitude)
    }

    // MARK: - Wake profile

    func saveWakeTraining(samples: [String]) {
        let cleaned = samples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        guard cleaned.count >= 3 else { return }

        var phrases = Set(cleaned.map { Self.normalizeWake($0) })
        // Wyodrębnij powtarzające się tokeny jako warianty
        for s in cleaned {
            let n = Self.normalizeWake(s)
            phrases.insert(n)
            if n.contains("drive") || n.contains("drajw") || n.contains("mate") {
                phrases.insert(n)
            }
        }
        wakeProfile = WakePronunciationMemory(
            samples: Array(cleaned.prefix(3)),
            learnedPhrases: Array(phrases).sorted(),
            trainedAt: .now
        )
        persistWake()
    }

    func clearWakeProfile() {
        wakeProfile = .empty
        persistWake()
    }

    var learnedWakePhrases: [String] {
        wakeProfile.learnedPhrases
    }

    static func normalizeWake(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Clear all

    func clearAllPersonalization() {
        clearVisits()
        clearAvoidances()
        clearWakeProfile()
    }

    // MARK: - Geometry helpers

    private static func distanceToRoute(_ coordinate: CLLocationCoordinate2D, route: MKRoute) -> CLLocationDistance {
        let poly = route.polyline
        let pointCount = poly.pointCount
        guard pointCount > 1 else { return .greatestFiniteMagnitude }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        let user = MKMapPoint(coordinate)
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(pointCount - 1) {
            let a = MKMapPoint(coords[i])
            let b = MKMapPoint(coords[i + 1])
            let d = distancePointToSegment(user, a, b)
            if d < best { best = d }
        }
        // MKMapPoint distance is in map points; convert roughly via meters-per-point near user.
        let metersPerPoint = MKMetersPerMapPointAtLatitude(coordinate.latitude)
        return best * metersPerPoint
    }

    private static func distancePointToSegment(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if dx == 0, dy == 0 {
            let ex = p.x - a.x
            let ey = p.y - a.y
            return sqrt(ex * ex + ey * ey)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let ex = p.x - projX
        let ey = p.y - projY
        return sqrt(ex * ex + ey * ey)
    }

    private static func nearestStepName(to coordinate: CLLocationCoordinate2D, route: MKRoute) -> String? {
        let user = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var best: (name: String, dist: CLLocationDistance)?
        for step in route.steps {
            let name = step.instructions
            guard !name.isEmpty else { continue }
            let poly = step.polyline
            guard poly.pointCount > 0 else { continue }
            var c = kCLLocationCoordinate2DInvalid
            poly.getCoordinates(&c, range: NSRange(location: 0, length: 1))
            let d = user.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if best == nil || d < best!.dist {
                // Wyciągnij potencjalną nazwę ulicy z instrukcji
                let street = extractStreetHint(from: name) ?? name
                best = (street, d)
            }
        }
        return best?.name
    }

    private static func extractStreetHint(from instruction: String) -> String? {
        let lower = instruction.lowercased()
        let markers = ["na ulicę ", "na ulice ", "ulicą ", "ulica ", "onto ", "on "]
        for m in markers {
            if let r = lower.range(of: m) {
                let rest = instruction[r.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                let token = rest.split(separator: " ").prefix(3).joined(separator: " ")
                if token.count >= 3 { return token }
            }
        }
        return nil
    }

    // MARK: - Persist

    private func load() {
        if let data = UserDefaults.standard.data(forKey: visitsKey),
           let decoded = try? JSONDecoder().decode([VisitedPlaceMemory].self, from: data) {
            visits = decoded
            pruneVisits()
        }
        if let data = UserDefaults.standard.data(forKey: avoidKey),
           let decoded = try? JSONDecoder().decode([RouteAvoidanceMemory].self, from: data) {
            avoidances = decoded
        }
        if let data = UserDefaults.standard.data(forKey: wakeKey),
           let decoded = try? JSONDecoder().decode(WakePronunciationMemory.self, from: data) {
            wakeProfile = decoded
        }
    }

    private func persistVisits() {
        if let data = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(data, forKey: visitsKey)
        }
    }

    private func persistAvoidances() {
        if let data = try? JSONEncoder().encode(avoidances) {
            UserDefaults.standard.set(data, forKey: avoidKey)
        }
    }

    private func persistWake() {
        if let data = try? JSONEncoder().encode(wakeProfile) {
            UserDefaults.standard.set(data, forKey: wakeKey)
        }
    }
}
