import Foundation
import MapKit
import CoreLocation
import Combine
import SwiftUI

enum TurnDirection: Equatable {
    case left
    case right
    case straight

    var spoken: String {
        switch self {
        case .left: "w lewo"
        case .right: "w prawo"
        case .straight: "prosto"
        }
    }

    var symbolName: String {
        switch self {
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .straight: "arrow.up"
        }
    }
}

struct TurnManeuver: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let heading: CLLocationDirection
    let instruction: String
    let direction: TurnDirection
    let stepDistance: CLLocationDistance

    var isLeft: Bool { direction == .left }
    var isRight: Bool { direction == .right }

    static func == (lhs: TurnManeuver, rhs: TurnManeuver) -> Bool {
        lhs.id == rhs.id
    }
}

struct NextTurnGuidance: Equatable {
    let maneuverID: UUID
    let direction: TurnDirection
    let distanceMeters: CLLocationDistance
    let instruction: String

    var isImminent: Bool { distanceMeters <= 50 }

    var distanceLabel: String {
        if isImminent { return "tutaj" }
        if distanceMeters >= 1000 {
            let km = distanceMeters / 1000
            return String(format: km >= 10 ? "%.0f km" : "%.1f km", km)
        }
        let rounded = Int((distanceMeters / 10).rounded() * 10)
        return "\(max(rounded, 10)) m"
    }
}

struct TripSummary: Equatable {
    let durationSeconds: TimeInterval
    let distanceMeters: CLLocationDistance
    let averageSpeedKmh: Double
    let destinationTitle: String?

    var durationLabel: String {
        let total = max(0, Int(durationSeconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d h %02d min", h, m)
        }
        if m > 0 {
            return String(format: "%d min %02d s", m, s)
        }
        return "\(s) s"
    }

    var distanceLabel: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters.rounded())) m"
    }

    var averageSpeedLabel: String {
        String(format: "%.0f km/h", averageSpeedKmh)
    }
}

/// Stan nawigacji na mapie Drive.
@MainActor
final class NavigationMapState: ObservableObject {
    enum CameraFocus: Equatable {
        case user
        case destination
        case route
        case follow
    }

    @Published var destinationCoordinate: CLLocationCoordinate2D?
    @Published var destinationTitle: String?
    @Published var route: MKRoute?
    @Published var alternateRoutes: [MKRoute] = []
    @Published var cameraFocus: CameraFocus = .user
    @Published var statusBanner: String?
    @Published var animateDestinationPulse = false
    @Published var isNavigating = false
    @Published var isFollowingUser = true
    @Published var showRecenterButton = false
    @Published var turnManeuvers: [TurnManeuver] = []
    @Published var nextTurnBanner: String?
    @Published var nextTurnGuidance: NextTurnGuidance?
    /// Jednorazowy komunikat głosowy przy zbliżeniu do skrętu.
    @Published var turnAnnouncement: String?
    /// 0…1 — postęp animacji „rysowania” linii trasy.
    @Published var routeDrawProgress: CGFloat = 1
    /// Trwa intro: kamera na trasie, bez follow użytkownika.
    @Published var isAnimatingRouteReveal = false
    /// Punkt, za którym podąża kamera podczas rysowania trasy.
    @Published var routeRevealCameraCoordinate: CLLocationCoordinate2D?
    /// Flaga celu — pojawia się dopiero na końcu rysowania.
    @Published var destinationFlagVisible = false
    /// Inkrementowane, by wywołać podskok flagi.
    @Published var destinationFlagBounceToken: Int = 0

    private var announcedManeuverIDs: Set<UUID> = []
    private var passedManeuverIDs: Set<UUID> = []
    private var routeRevealTask: Task<Void, Never>?

    // Trip stats
    private var tripStartedAt: Date?
    private var tripDistanceMeters: CLLocationDistance = 0
    private var lastTripLocation: CLLocation?

    var hasActiveRoute: Bool { route != nil && isNavigating }

    func clearNavigation() {
        routeRevealTask?.cancel()
        routeRevealTask = nil
        destinationCoordinate = nil
        destinationTitle = nil
        route = nil
        alternateRoutes = []
        cameraFocus = .user
        statusBanner = nil
        animateDestinationPulse = false
        isNavigating = false
        isFollowingUser = true
        showRecenterButton = false
        turnManeuvers = []
        nextTurnBanner = nil
        nextTurnGuidance = nil
        turnAnnouncement = nil
        routeDrawProgress = 1
        isAnimatingRouteReveal = false
        routeRevealCameraCoordinate = nil
        destinationFlagVisible = false
        announcedManeuverIDs.removeAll()
        passedManeuverIDs.removeAll()
        resetTripTracking()
    }

    /// Kończy trasę i zwraca podsumowanie (czas, dystans, średnia prędkość).
    func endTripAndSummarize() -> TripSummary {
        let summary = makeTripSummary()
        clearNavigation()
        return summary
    }

    func trackTripProgress(userCoordinate: CLLocationCoordinate2D?) {
        guard isNavigating, let userCoordinate else { return }
        let loc = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        if let last = lastTripLocation {
            let delta = loc.distance(from: last)
            // Ignoruj szum GPS i skoki.
            if delta >= 4, delta < 120 {
                tripDistanceMeters += delta
                lastTripLocation = loc
            } else if delta >= 120 {
                // Teleport / glitch — tylko aktualizuj punkt.
                lastTripLocation = loc
            }
        } else {
            lastTripLocation = loc
        }
    }

    private func beginTripTracking() {
        tripStartedAt = Date()
        tripDistanceMeters = 0
        lastTripLocation = nil
    }

    private func resetTripTracking() {
        tripStartedAt = nil
        tripDistanceMeters = 0
        lastTripLocation = nil
    }

    private func makeTripSummary() -> TripSummary {
        let elapsed = Date().timeIntervalSince(tripStartedAt ?? Date())
        let duration = max(elapsed, 1)
        let distance = max(tripDistanceMeters, 0)
        let hours = duration / 3600
        let avg = hours > 0 ? (distance / 1000) / hours : 0
        return TripSummary(
            durationSeconds: duration,
            distanceMeters: distance,
            averageSpeedKmh: avg,
            destinationTitle: destinationTitle
        )
    }

    func presentDestination(
        coordinate: CLLocationCoordinate2D,
        title: String,
        route: MKRoute?,
        alternates: [MKRoute]
    ) {
        routeRevealTask?.cancel()
        destinationCoordinate = coordinate
        destinationTitle = title
        self.route = route
        alternateRoutes = alternates
        turnManeuvers = Self.buildManeuvers(from: route)
        nextTurnBanner = turnManeuvers.first?.instruction
        nextTurnGuidance = nil
        turnAnnouncement = nil
        announcedManeuverIDs.removeAll()
        passedManeuverIDs.removeAll()
        isNavigating = route != nil
        animateDestinationPulse = true
        statusBanner = "Nawigacja · \(title)"
        showRecenterButton = false

        if route != nil {
            beginTripTracking()
            isFollowingUser = false
            isAnimatingRouteReveal = true
            destinationFlagVisible = false
            routeDrawProgress = 0
            // Start kamery na początku trasy
            if let poly = route?.polyline,
               let start = RouteGeometry.coordinate(along: poly, progress: 0) {
                routeRevealCameraCoordinate = start
            } else {
                routeRevealCameraCoordinate = nil
            }
            cameraFocus = .follow
            startRouteRevealAnimation()
        } else {
            isFollowingUser = true
            isAnimatingRouteReveal = false
            routeDrawProgress = 1
            destinationFlagVisible = true
            routeRevealCameraCoordinate = nil
            cameraFocus = .destination
        }
    }

    private func startRouteRevealAnimation() {
        routeRevealTask?.cancel()
        routeRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, isNavigating, isAnimatingRouteReveal else { return }
            guard let polyline = route?.polyline else { return }

            let duration: Double = 2.55 * 1.5
            let steps = 64
            for i in 1...steps {
                guard !Task.isCancelled, isNavigating, isAnimatingRouteReveal else { return }
                let t = Double(i) / Double(steps)
                // Lekki ease-in-out — kamera „jedzie” z linią
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                let progress = CGFloat(eased)
                routeDrawProgress = progress
                if let tip = RouteGeometry.coordinate(along: polyline, progress: progress) {
                    routeRevealCameraCoordinate = tip
                }
                try? await Task.sleep(nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000))
            }
            routeDrawProgress = 1
            if let end = RouteGeometry.coordinate(along: polyline, progress: 1)
                ?? destinationCoordinate {
                routeRevealCameraCoordinate = end
            }

            // Flaga na celu + lekki podskok
            destinationFlagVisible = true
            destinationFlagBounceToken &+= 1
            try? await Task.sleep(nanoseconds: 950_000_000)
            guard !Task.isCancelled, isNavigating else { return }

            // Wróć do wycentrowanej lokalizacji usera
            isAnimatingRouteReveal = false
            routeRevealCameraCoordinate = nil
            isFollowingUser = true
            cameraFocus = .user
            cameraFocus = .follow
        }
    }

    func userPannedMap() {
        guard isNavigating else { return }
        isFollowingUser = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            showRecenterButton = true
        }
    }

    func recenterOnUser() {
        isFollowingUser = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            showRecenterButton = false
        }
        cameraFocus = .user
        cameraFocus = .follow
    }

    func consumeTurnAnnouncement() {
        turnAnnouncement = nil
    }

    /// Aktualizuj odległość do następnego manewru na podstawie GPS.
    func updateGuidance(userCoordinate: CLLocationCoordinate2D?) {
        guard isNavigating, let userCoordinate else {
            nextTurnGuidance = nil
            return
        }
        let user = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)

        for m in turnManeuvers where !passedManeuverIDs.contains(m.id) {
            let d = user.distance(from: CLLocation(latitude: m.coordinate.latitude, longitude: m.coordinate.longitude))
            if d < 25 {
                passedManeuverIDs.insert(m.id)
            }
        }

        guard let next = turnManeuvers.first(where: { !passedManeuverIDs.contains($0.id) }) else {
            nextTurnGuidance = nil
            nextTurnBanner = nil
            return
        }

        let distance = user.distance(
            from: CLLocation(latitude: next.coordinate.latitude, longitude: next.coordinate.longitude)
        )
        let guidance = NextTurnGuidance(
            maneuverID: next.id,
            direction: next.direction,
            distanceMeters: distance,
            instruction: next.instruction
        )
        nextTurnGuidance = guidance
        nextTurnBanner = next.instruction

        if guidance.isImminent, !announcedManeuverIDs.contains(next.id) {
            announcedManeuverIDs.insert(next.id)
            switch next.direction {
            case .straight:
                turnAnnouncement = "Na najbliższym skrzyżowaniu jedź prosto."
            case .left, .right:
                turnAnnouncement = "Na najbliższym skrzyżowaniu skręć \(next.direction.spoken)."
            }
        }
    }

    private static func buildManeuvers(from route: MKRoute?) -> [TurnManeuver] {
        guard let route else { return [] }
        var result: [TurnManeuver] = []
        for step in route.steps {
            let text = step.instructions.lowercased()
            let direction = classifyDirection(text)
            let isTurn = direction == .left || direction == .right
                || text.contains("skręć") || text.contains("skrec")
                || text.contains("turn") || text.contains("zjedź") || text.contains("zjazd")
            guard isTurn, step.distance > 5 else { continue }

            let line = step.polyline
            guard line.pointCount > 0 else { continue }
            var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: line.pointCount)
            line.getCoordinates(&points, range: NSRange(location: 0, length: line.pointCount))
            guard let first = points.first else { continue }

            var heading: CLLocationDirection = 0
            if points.count >= 2 {
                heading = bearing(from: points[0], to: points[min(1, points.count - 1)])
            }

            result.append(
                TurnManeuver(
                    id: UUID(),
                    coordinate: first,
                    heading: heading,
                    instruction: step.instructions,
                    direction: direction == .straight
                        ? (text.contains("lewo") || text.contains("left") ? .left
                           : text.contains("prawo") || text.contains("right") ? .right : .straight)
                        : direction,
                    stepDistance: step.distance
                )
            )
        }
        return result
    }

    private static func classifyDirection(_ text: String) -> TurnDirection {
        if text.contains("lewo") || text.contains("left") { return .left }
        if text.contains("prawo") || text.contains("right") { return .right }
        if text.contains("prosto") || text.contains("straight") || text.contains("kontynuuj") {
            return .straight
        }
        return .straight
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// MapKit — wyszukiwanie, ETA, trasa.
@MainActor
final class MapKitNavigationService {
    static let shared = MapKitNavigationService()

    weak var mapState: NavigationMapState?
    weak var location: LocationSpeedService?

    struct PlaceResult: Sendable {
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let category: String
    }

    struct RouteResult: Sendable {
        let name: String
        let distanceMeters: Double
        let expectedSeconds: Double
        let hasToll: Bool
        let advisoryNotices: [String]
        let summary: String
    }

    func searchPlaces(
        query: String,
        near coordinate: CLLocationCoordinate2D?,
        presentOnMap: Bool = true
    ) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 80_000,
                longitudinalMeters: 80_000
            )
        }

        let response = try await MKLocalSearch(request: request).start()
        let places = response.mapItems.prefix(8).compactMap { item in
            Self.mapItemToPlace(item, fallbackName: query)
        }
        if presentOnMap, !places.isEmpty {
            MapComplianceStore.shared.showPlaces(
                title: query,
                pins: places.map {
                    (CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), $0.name)
                },
                center: places.first.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                },
                spanMeters: 3_500
            )
        }
        return Array(places)
    }

    /// Najbliższa restauracja (Apple Maps POI).
    func findNearestRestaurant(
        near coordinate: CLLocationCoordinate2D
    ) async throws -> (place: PlaceResult, mapItem: MKMapItem)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restauracja"
        request.resultTypes = [.pointOfInterest]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket])
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 8_000,
            longitudinalMeters: 8_000
        )
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let ranked = response.mapItems.compactMap { item -> (PlaceResult, MKMapItem, CLLocationDistance)? in
            guard let place = Self.mapItemToPlace(item, fallbackName: "Restauracja") else { return nil }
            let d = origin.distance(
                from: CLLocation(latitude: place.latitude, longitude: place.longitude)
            )
            return (place, item, d)
        }
        .sorted { $0.2 < $1.2 }

        guard let best = ranked.first else { return nil }
        return (best.0, best.1)
    }

    /// Najbliższe stacje paliw (Apple Maps POI).
    func findNearbyGasStations(
        near coordinate: CLLocationCoordinate2D,
        limit: Int = 5
    ) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "stacja paliw"
        request.resultTypes = [.pointOfInterest]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 12_000,
            longitudinalMeters: 12_000
        )
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let ranked = response.mapItems.compactMap { item -> (PlaceResult, CLLocationDistance)? in
            guard let place = Self.mapItemToPlace(item, fallbackName: "Stacja paliw") else { return nil }
            let d = origin.distance(
                from: CLLocation(latitude: place.latitude, longitude: place.longitude)
            )
            return (place, d)
        }
        .sorted { $0.1 < $1.1 }
        return Array(ranked.prefix(max(limit, 1)).map(\.0))
    }

    /// Szybkie wyszukanie pierwszego trafienia (nawigacja).
    func findFirstPlace(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> PlaceResult? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 45_000,
                longitudinalMeters: 45_000
            )
        }
        let response = try await MKLocalSearch(request: request).start()
        let place = response.mapItems.lazy.compactMap { Self.mapItemToPlace($0, fallbackName: query) }.first
        if let place {
            MapComplianceStore.shared.showPlace(
                name: place.name,
                coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            )
        }
        return place
    }

    private static func mapItemToPlace(_ item: MKMapItem, fallbackName: String) -> PlaceResult? {
        let coord = item.location.coordinate
        if abs(coord.latitude) < 0.0001, abs(coord.longitude) < 0.0001 { return nil }
        let address = [
            item.placemark.thoroughfare,
            item.placemark.subThoroughfare,
            item.placemark.locality
        ].compactMap { $0 }.joined(separator: " ")
        return PlaceResult(
            name: item.name ?? fallbackName,
            address: address.isEmpty ? (item.placemark.title ?? "") : address,
            latitude: coord.latitude,
            longitude: coord.longitude,
            category: item.pointOfInterestCategory?.rawValue ?? "place"
        )
    }

    /// Cel wybrany głosem — czekamy na punkt startowy.
    struct PendingDestination: Equatable {
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
    }

    private(set) var pendingDestination: PendingDestination?

    func setPendingDestination(_ place: PlaceResult) {
        pendingDestination = PendingDestination(
            name: place.name,
            address: place.address,
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    func clearPendingDestination() {
        pendingDestination = nil
    }

    func planBestRoute(
        toLatitude: Double,
        toLongitude: Double,
        destinationName: String,
        fromLatitude: Double? = nil,
        fromLongitude: Double? = nil
    ) async throws -> (best: RouteResult, alternates: [RouteResult]) {
        guard NavigationEULA.isAccepted else {
            throw NavigationError.disclaimerRequired
        }

        let destCoord = CLLocationCoordinate2D(latitude: toLatitude, longitude: toLongitude)
        let destination = MKMapItem(
            location: CLLocation(latitude: toLatitude, longitude: toLongitude),
            address: nil
        )
        destination.name = destinationName

        let source: MKMapItem
        if let fromLatitude, let fromLongitude {
            source = MKMapItem(
                location: CLLocation(latitude: fromLatitude, longitude: fromLongitude),
                address: nil
            )
            source.name = "Start"
        } else if let from = location?.coordinate {
            source = MKMapItem(
                location: CLLocation(latitude: from.latitude, longitude: from.longitude),
                address: nil
            )
        } else {
            source = .forCurrentLocation()
        }

        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .automobile

        let prefs = DriveMateMemoryStore.shared.activeAvoidances(near: destCoord)
        let useAlternates = !prefs.isEmpty
        request.requestsAlternateRoutes = useAlternates

        let response = try await MKDirections(request: request).calculate()
        guard let first = response.routes.first else { throw NavigationError.noRoute }

        let best: MKRoute
        if useAlternates, response.routes.count > 1 {
            best = Self.pickPreferredRoute(from: response.routes, preferences: prefs) ?? first
        } else if let waypointRoute = await Self.routeViaPreferredWaypoints(
            source: source,
            destination: destination,
            preferences: prefs
        ) {
            best = waypointRoute
        } else {
            best = first
        }

        let mappedRoutes = (useAlternates ? response.routes : [best]).map { route -> RouteResult in
            let minutes = Int((route.expectedTravelTime / 60).rounded())
            let km = route.distance / 1000
            let notices = route.advisoryNotices
            return RouteResult(
                name: route.name.isEmpty ? "Trasa samochodowa" : route.name,
                distanceMeters: route.distance,
                expectedSeconds: route.expectedTravelTime,
                hasToll: false,
                advisoryNotices: notices,
                summary: String(
                    format: "%@ · %.1f km · ok. %d min%@",
                    route.name.isEmpty ? "Trasa" : route.name,
                    km,
                    minutes,
                    notices.isEmpty ? "" : " · uwagi: \(notices.joined(separator: ", "))"
                )
            )
        }

        guard let mapState else { throw NavigationError.noRoute }
        clearPendingDestination()
        // Pełna mapa nawigacji zastępuje podgląd compliance
        MapComplianceStore.shared.clear()
        mapState.presentDestination(
            coordinate: destCoord,
            title: destinationName,
            route: best,
            alternates: []
        )

        let bestResult = mappedRoutes.first(where: {
            abs($0.distanceMeters - best.distance) < 1
                && abs($0.expectedSeconds - best.expectedTravelTime) < 1
        }) ?? RouteResult(
            name: best.name.isEmpty ? "Trasa samochodowa" : best.name,
            distanceMeters: best.distance,
            expectedSeconds: best.expectedTravelTime,
            hasToll: false,
            advisoryNotices: best.advisoryNotices,
            summary: String(
                format: "%@ · %.1f km · ok. %d min",
                best.name.isEmpty ? "Trasa" : best.name,
                best.distance / 1000,
                Int((best.expectedTravelTime / 60).rounded())
            )
        )

        return (bestResult, [])
    }

    /// Wybierz trasę omijającą ulice, których user unika (≥3×).
    private static func pickPreferredRoute(
        from routes: [MKRoute],
        preferences: [RouteAvoidanceMemory]
    ) -> MKRoute? {
        guard !preferences.isEmpty else { return routes.first }
        let avoided = preferences.map { $0.avoidedStreetName.lowercased() }
        var scored: [(MKRoute, Int)] = []
        for route in routes {
            var penalty = 0
            let blob = (
                [route.name] + route.steps.map(\.instructions)
            ).joined(separator: " ").lowercased()
            for street in avoided {
                if blob.contains(street.lowercased()) { penalty += 3 }
            }
            // Lekki bonus za podobieństwo do wyuczonej ścieżki GPS
            if let samples = preferences.first(where: { !$0.preferredCoordinates.isEmpty })?.preferredCoordinates,
               samples.count >= 2 {
                let overlap = pathOverlapScore(route: route, samples: samples)
                penalty -= Int(overlap * 4)
            }
            scored.append((route, penalty))
        }
        return scored.min(by: { $0.1 < $1.1 })?.0
    }

    private static func pathOverlapScore(route: MKRoute, samples: [CLLocationCoordinate2D]) -> Double {
        let poly = route.polyline
        let count = poly.pointCount
        guard count > 1, !samples.isEmpty else { return 0 }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        var hits = 0
        for sample in samples {
            let s = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
            let near = coords.contains { c in
                s.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 120
            }
            if near { hits += 1 }
        }
        return Double(hits) / Double(samples.count)
    }

    /// Gdy jest wyuczona ścieżka — wybierz (przy ponownym calculate z alternatywami) trasę bliższą próbkom.
    private static func routeViaPreferredWaypoints(
        source: MKMapItem,
        destination: MKMapItem,
        preferences: [RouteAvoidanceMemory]
    ) async -> MKRoute? {
        let samples = preferences.first(where: { $0.preferredCoordinates.count >= 2 })?.preferredCoordinates
        guard let samples, samples.count >= 2 else { return nil }

        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        do {
            let response = try await MKDirections(request: request).calculate()
            guard !response.routes.isEmpty else { return nil }
            return response.routes.max(by: { a, b in
                pathOverlapScore(route: a, samples: samples) < pathOverlapScore(route: b, samples: samples)
            })
        } catch {
            return nil
        }
    }

    /// Ocena ruchu: jedna trasa MKDirections prezentowana na mapie Apple + warstwa ruchu.
    func trafficSnapshot(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 2500
    ) async throws -> String {
        let sourceCoord = location?.coordinate ?? coordinate
        let source = MKMapItem(
            location: CLLocation(latitude: sourceCoord.latitude, longitude: sourceCoord.longitude),
            address: nil
        )
        let dest = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        dest.name = "Punkt oceny ruchu"

        let request = MKDirections.Request()
        request.source = source
        request.destination = dest
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        // Jedna trasa — zawsze pokazywana użytkownikowi na mapie Apple (wymóg MKDirections + §2.4)
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            MapComplianceStore.shared.showTraffic(near: coordinate, title: "Ruch (Apple Maps)", route: nil)
            return "Otworzono mapę Apple z warstwą ruchu. Brak szczegółowej trasy w tej okolicy."
        }

        MapComplianceStore.shared.showTraffic(
            near: coordinate,
            title: "Ruch (Apple Maps)",
            route: route
        )

        let minutes = Int((route.expectedTravelTime / 60).rounded())
        let km = route.distance / 1000
        let notices = route.advisoryNotices
        let speed = km / max(route.expectedTravelTime / 3600, 0.01)
        let congestion: String
        if speed < 18 { congestion = "możliwe utrudnienia" }
        else if speed < 28 { congestion = "umiarkowany ruch" }
        else { congestion = "raczej płynnie" }

        var text = String(
            format: "Trasa do punktu na mapie Apple: %.1f km, ok. %d min (%@).",
            km,
            minutes,
            congestion
        )
        if !notices.isEmpty {
            text += " Uwagi: " + notices.joined(separator: ", ") + "."
        }
        text += " Warstwa ruchu jest widoczna na mapie."
        return text
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> CLPlacemark {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
        guard let placemark = placemarks.first else { throw NavigationError.geocodeFailed }
        return placemark
    }
}

enum NavigationError: LocalizedError {
    case noUserLocation
    case noRoute
    case geocodeFailed
    case disclaimerRequired

    var errorDescription: String? {
        switch self {
        case .noUserLocation: "Brak lokalizacji użytkownika."
        case .noRoute: "Nie znaleziono trasy."
        case .geocodeFailed: "Nie udało się odczytać adresu."
        case .disclaimerRequired: "Najpierw zaakceptuj warunki nawigacji w czasie rzeczywistym."
        }
    }
}

/// Geometria trasy MKPolyline — punkt / heading przy danym progress 0…1.
enum RouteGeometry {
    static func coordinate(along polyline: MKPolyline, progress: CGFloat) -> CLLocationCoordinate2D? {
        guard polyline.pointCount > 0 else { return nil }
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        guard coords.count > 1 else { return coords.first }
        return point(along: coords, progress: min(max(progress, 0), 1)).coordinate
    }

    static func heading(along polyline: MKPolyline, progress: CGFloat) -> CLLocationDirection {
        guard polyline.pointCount > 1 else { return 0 }
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        let sample = point(along: coords, progress: min(max(progress, 0), 1))
        let lookAhead = point(along: coords, progress: min(max(progress + 0.02, 0), 1))
        return bearing(from: sample.coordinate, to: lookAhead.coordinate)
    }

    private struct Sample {
        let coordinate: CLLocationCoordinate2D
        let index: Int
    }

    private static func point(along coords: [CLLocationCoordinate2D], progress: CGFloat) -> Sample {
        guard coords.count > 1 else {
            return Sample(coordinate: coords[0], index: 0)
        }
        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            let d = CGFloat(a.distance(from: b))
            lengths.append(d)
            total += d
        }
        guard total > 0 else { return Sample(coordinate: coords[0], index: 0) }

        let target = total * progress
        var traveled: CGFloat = 0
        for i in 1..<coords.count {
            let seg = lengths[i - 1]
            if traveled + seg >= target {
                let t = seg > 0 ? (target - traveled) / seg : 0
                let c = interpolate(coords[i - 1], coords[i], t: t)
                return Sample(coordinate: c, index: i - 1)
            }
            traveled += seg
        }
        return Sample(coordinate: coords[coords.count - 1], index: coords.count - 2)
    }

    private static func interpolate(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        t: CGFloat
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * Double(t),
            longitude: a.longitude + (b.longitude - a.longitude) * Double(t)
        )
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension Notification.Name {
    static let driveMateDidNavigate = Notification.Name("driveMateDidNavigate")
    static let driveMateDidSelectDestination = Notification.Name("driveMateDidSelectDestination")
    static let driveMateNeedsNavEULA = Notification.Name("driveMateNeedsNavEULA")
    static let driveMateDidCancelRoute = Notification.Name("driveMateDidCancelRoute")
}
