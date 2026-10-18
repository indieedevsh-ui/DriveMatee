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
    /// Kafelek skrętu widoczny dopiero od tej odległości (dalej — przycisk oczu Drive Mate).
    static let tileVisibleWithinMeters: CLLocationDistance = 350
    /// W trybie AR — symbol skrętu na środku kamery od tej odległości.
    static let arApproachWithinMeters: CLLocationDistance = 100
    /// Próg „jesteś na skrzyżowaniu” — przypomnienie AR na 5 s.
    static let arIntersectionWithinMeters: CLLocationDistance = 40

    let maneuverID: UUID
    let direction: TurnDirection
    let distanceMeters: CLLocationDistance
    let instruction: String

    var isImminent: Bool { distanceMeters <= 50 }

    /// Czy pokazać kafelek zamiast przycisku Drive Mate.
    var showsTurnTile: Bool { distanceMeters <= Self.tileVisibleWithinMeters }

    var showsARApproachSymbol: Bool {
        distanceMeters <= Self.arApproachWithinMeters && direction != .straight
    }

    var isAtIntersectionForAR: Bool {
        distanceMeters <= Self.arIntersectionWithinMeters && direction != .straight
    }

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
    /// Inkrementowane gdy trzeba wystartować rysowanie linii (mapa musi być gotowa).
    @Published private(set) var routeRevealRequestID: Int = 0
    /// Inkrementowane przy każdym „wyśrodkuj” — mapa zawsze reaguje, nawet gdy focus już był `.follow`.
    @Published private(set) var recenterRequestID: Int = 0

    private var announcedManeuverIDs: Set<UUID> = []
    /// Zapowiedź „za X metrów” (wcześniejsza niż imminent).
    private var approachAnnouncedIDs: Set<UUID> = []
    private var passedManeuverIDs: Set<UUID> = []
    private var routeRevealTask: Task<Void, Never>?
    /// Czekamy na MapDriveView — animacja nie może lecieć „w próżnię”.
    private var routeRevealAwaitingMap = false
    /// Blokada auto-przeliczania trasy (żeby nie spamować MapKit).
    private var lastRerouteAt: Date?
    private var offRouteTicksForReroute = 0
    private var rerouteTask: Task<Void, Never>?

    // Trip stats
    private var tripStartedAt: Date?
    private var tripDistanceMeters: CLLocationDistance = 0
    private var lastTripLocation: CLLocation?

    var hasActiveRoute: Bool { route != nil && isNavigating }

    func clearNavigation() {
        routeRevealTask?.cancel()
        routeRevealTask = nil
        routeRevealAwaitingMap = false
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
        approachAnnouncedIDs.removeAll()
        passedManeuverIDs.removeAll()
        lastRerouteAt = nil
        offRouteTicksForReroute = 0
        rerouteTask?.cancel()
        rerouteTask = nil
        resetTripTracking()
    }

    /// Kończy trasę i zwraca podsumowanie (czas, dystans, średnia prędkość).
    func endTripAndSummarize() -> TripSummary {
        let summary = makeTripSummary()
        // Spalenie z trasy zmniejsza poziom w baku — zasięg ma być prawdziwy.
        FuelProfile.shared.consume(distanceMeters: summary.distanceMeters)
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
        alternates: [MKRoute],
        animateReveal: Bool = true,
        resetTripStats: Bool = true
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
        approachAnnouncedIDs.removeAll()
        passedManeuverIDs.removeAll()
        isNavigating = route != nil
        animateDestinationPulse = true
        statusBanner = "Nawigacja · \(title)"
        showRecenterButton = false

        if route != nil {
            if resetTripStats {
                beginTripTracking()
            }
            if animateReveal {
                isFollowingUser = false
                isAnimatingRouteReveal = true
                destinationFlagVisible = false
                routeDrawProgress = 0
                if let poly = route?.polyline,
                   let start = RouteGeometry.coordinate(along: poly, progress: 0) {
                    routeRevealCameraCoordinate = start
                } else {
                    routeRevealCameraCoordinate = nil
                }
                cameraFocus = .follow
                routeRevealAwaitingMap = true
                routeRevealRequestID &+= 1
            } else {
                // Ciche przeliczenie trasy — od razu follow, bez rysowania linii.
                isFollowingUser = true
                isAnimatingRouteReveal = false
                destinationFlagVisible = true
                routeDrawProgress = 1
                routeRevealCameraCoordinate = nil
                routeRevealAwaitingMap = false
                cameraFocus = .follow
                recenterRequestID &+= 1
            }
        } else {
            isFollowingUser = true
            isAnimatingRouteReveal = false
            routeDrawProgress = 1
            destinationFlagVisible = true
            routeRevealCameraCoordinate = nil
            cameraFocus = .destination
            routeRevealAwaitingMap = false
        }
    }

    /// Wywołaj z MapDriveView gdy MKMapView jest gotowy (onAppear / nowa trasa).
    func startRouteRevealWhenMapReady() {
        guard routeRevealAwaitingMap, isNavigating, route?.polyline != nil else { return }
        routeRevealAwaitingMap = false
        startRouteRevealAnimation()
    }

    private func startRouteRevealAnimation() {
        routeRevealTask?.cancel()
        isAnimatingRouteReveal = true
        destinationFlagVisible = false
        routeDrawProgress = 0
        if let poly = route?.polyline,
           let start = RouteGeometry.coordinate(along: poly, progress: 0) {
            routeRevealCameraCoordinate = start
        }

        routeRevealTask = Task { @MainActor in
            // Daj MKMapView czas na utworzenie LimeRouteRenderer.
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, isNavigating, isAnimatingRouteReveal else { return }
            guard let polyline = route?.polyline else { return }

            let duration: Double = 3.2
            let steps = 72
            let stepNs = UInt64((duration / Double(steps)) * 1_000_000_000)
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
                try? await Task.sleep(nanoseconds: stepNs)
            }
            guard !Task.isCancelled, isNavigating else { return }
            routeDrawProgress = 1
            if let end = RouteGeometry.coordinate(along: polyline, progress: 1)
                ?? destinationCoordinate {
                routeRevealCameraCoordinate = end
            }

            // Flaga na celu + lekki podskok
            destinationFlagVisible = true
            destinationFlagBounceToken &+= 1
            try? await Task.sleep(nanoseconds: 850_000_000)
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
        // Przerwij intro rysowania trasy — inaczej kamera zostaje na czubku linii.
        if isAnimatingRouteReveal {
            routeRevealTask?.cancel()
            routeRevealTask = nil
            routeRevealAwaitingMap = false
            isAnimatingRouteReveal = false
            routeDrawProgress = 1
            destinationFlagVisible = true
            routeRevealCameraCoordinate = nil
        }

        isFollowingUser = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            showRecenterButton = false
        }
        // Najpierw fokus, potem token + notification — mapa nie może „zgubić” prośby.
        cameraFocus = isNavigating ? .follow : .user
        objectWillChange.send()
        recenterRequestID &+= 1
        NotificationCenter.default.post(name: .driveMateRecenterRequested, object: nil)
        // Drugi impuls po krótkiej chwili (mapa po AR / pierwszym layoucie).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.isFollowingUser = true
            self.cameraFocus = self.isNavigating ? .follow : .user
            self.recenterRequestID &+= 1
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .driveMateRecenterRequested, object: nil)
        }
    }

    func consumeTurnAnnouncement() {
        turnAnnouncement = nil
    }

    /// Następny manewr + dystans — także gdy kafelek skrętu jeszcze niewidoczny (>350 m).
    func nextManeuverSnapshot(userCoordinate: CLLocationCoordinate2D?) -> (maneuver: TurnManeuver, distanceMeters: CLLocationDistance)? {
        guard isNavigating else { return nil }
        let coord = userCoordinate
            ?? MapKitNavigationService.shared.location?.coordinate
        guard let coord else { return nil }
        let user = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let next = turnManeuvers.first(where: { !passedManeuverIDs.contains($0.id) }) else {
            return nil
        }
        let distance = user.distance(
            from: CLLocation(latitude: next.coordinate.latitude, longitude: next.coordinate.longitude)
        )
        return (next, distance)
    }

    /// Spokojna odpowiedź głosowa: kiedy i gdzie skręcić.
    func spokenNextTurnAdvice(userCoordinate: CLLocationCoordinate2D?) -> String {
        guard isNavigating else {
            return "Nie mam aktywnej trasy — najpierw wybierz cel."
        }
        guard let snap = nextManeuverSnapshot(userCoordinate: userCoordinate) else {
            return "Do celu jedziesz już bez kolejnego skrętu — trzymaj się trasy."
        }
        let m = snap.maneuver
        let distance = snap.distanceMeters
        let place = Self.spokenIntersectionLabel(from: m.instruction)
        let when: String = {
            if distance <= 40 {
                return "teraz"
            }
            if distance < 1000 {
                let meters = Int((distance / 10).rounded() * 10)
                return "za \(max(meters, 10)) metrów"
            }
            let km = distance / 1000
            return String(format: km >= 10 ? "za %.0f kilometrów" : "za %.1f kilometra", km)
        }()

        var parts: [String] = []
        if m.direction == .straight {
            parts.append("\(when.prefix(1).uppercased())\(when.dropFirst()) na \(place) jedź prosto.")
        } else {
            parts.append("Skręć \(m.direction.spoken) \(when) — na \(place).")
        }
        let detail = m.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty, detail.count <= 140 {
            let foldedDetail = DriveIntentQueryHelpers.foldForMatching(detail)
            let foldedPlace = DriveIntentQueryHelpers.foldForMatching(place)
            if !foldedDetail.contains(foldedPlace) || detail.count > place.count + 8 {
                parts.append(detail)
            }
        }
        return parts.joined(separator: " ")
    }

    /// „rondzie …”, „skrzyżowaniu z ul. …”, albo ogólne „najbliższym skrzyżowaniu”.
    private static func spokenIntersectionLabel(from instruction: String) -> String {
        let raw = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = DriveIntentQueryHelpers.foldForMatching(raw)

        if folded.contains("rondo") {
            if let r = raw.range(of: #"(?i)rond[oa]\s+[^,.]+"#, options: .regularExpression) {
                var label = String(raw[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if label.lowercased().hasPrefix("rondo") {
                    // „rondo X” → „rondzie X”
                    label = "rondzie" + label.dropFirst(5)
                }
                return label
            }
            return "najbliższym rondzie"
        }

        // „Skręć w lewo w ulicę Floriańską” / „na skrzyżowaniu z …”
        if let r = raw.range(of: #"(?i)(?:w|na)\s+ulic[ęea]\s+[^,.]+"#, options: .regularExpression) {
            let street = String(raw[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return "skrzyżowaniu \(street)"
        }
        if let r = raw.range(of: #"(?i)skrzyżowani[ua]\s+[^,.]+"#, options: .regularExpression) {
            return String(raw[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if folded.contains("zjazd") || folded.contains("zjedz") {
            return "najbliższym zjeździe"
        }
        return "najbliższym skrzyżowaniu"
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
            // Później oznaczaj jako minięty — wcześniej gubiło zapowiedź głosową.
            if d < 18 {
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
        nextTurnBanner = next.instruction

        // Kafelek tylko blisko manewru — dalej wraca przycisk oczu Drive Mate.
        if distance <= NextTurnGuidance.tileVisibleWithinMeters {
            nextTurnGuidance = NextTurnGuidance(
                maneuverID: next.id,
                direction: next.direction,
                distanceMeters: distance,
                instruction: next.instruction
            )
        } else {
            nextTurnGuidance = nil
        }

        // Głos: wcześniej (≈180 m) + przypomnienie na skrzyżowaniu (≤50 m).
        let turnDirs: Set<TurnDirection> = [.left, .right]
        if turnDirs.contains(next.direction) {
            if distance <= 180, distance > 55, !approachAnnouncedIDs.contains(next.id) {
                approachAnnouncedIDs.insert(next.id)
                let meters = Int((distance / 10).rounded() * 10)
                turnAnnouncement = "Za \(max(meters, 60)) metrów skręć \(next.direction.spoken)."
            } else if distance <= 55, !announcedManeuverIDs.contains(next.id) {
                announcedManeuverIDs.insert(next.id)
                approachAnnouncedIDs.insert(next.id)
                turnAnnouncement = "Skręć \(next.direction.spoken)."
            }
        } else if next.direction == .straight, distance <= 55, !announcedManeuverIDs.contains(next.id) {
            announcedManeuverIDs.insert(next.id)
            turnAnnouncement = "Na najbliższym skrzyżowaniu jedź prosto."
        }
    }

    /// Po „chcę jechać prosto” trasa może kończyć się za skrzyżowaniem, a pin celu zostaje na finale —
    /// gdy zbliżysz się do końca odcinka bias, dociągnij trasę do właściwego celu.
    func considerManeuverBiasContinue(userCoordinate: CLLocationCoordinate2D?) {
        guard isNavigating,
              !isAnimatingRouteReveal,
              let userCoordinate,
              let route,
              let dest = destinationCoordinate,
              let title = destinationTitle else { return }
        guard let routeEnd = RouteGeometry.coordinate(along: route.polyline, progress: 1) else { return }
        let endToDest = CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)
            .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
        // Zwykła trasa kończy się przy pinie — nie ruszaj.
        guard endToDest > 180 else { return }
        let userToEnd = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude))
        guard userToEnd < 75 else { return }
        if let last = lastRerouteAt, Date().timeIntervalSince(last) < 8 { return }
        guard rerouteTask == nil else { return }

        lastRerouteAt = Date()
        let lat = userCoordinate.latitude
        let lon = userCoordinate.longitude
        let destLat = dest.latitude
        let destLon = dest.longitude
        let destTitle = title
        rerouteTask = Task { @MainActor in
            defer { rerouteTask = nil }
            do {
                _ = try await MapKitNavigationService.shared.planBestRoute(
                    toLatitude: destLat,
                    toLongitude: destLon,
                    destinationName: destTitle,
                    fromLatitude: lat,
                    fromLongitude: lon,
                    animateReveal: false,
                    resetTripStats: false
                )
            } catch { /* kolejny tick GPS */ }
        }
    }

    /// Auto-przelicz trasę, gdy kierowca zjedzie z polilinii (bez animacji rysowania).
    func considerAutoReroute(userCoordinate: CLLocationCoordinate2D?) {
        guard isNavigating,
              !isAnimatingRouteReveal,
              let userCoordinate,
              let route,
              let dest = destinationCoordinate,
              let title = destinationTitle else {
            offRouteTicksForReroute = 0
            return
        }

        let dist = DriveMateMemoryStore.distanceToRoutePolyline(userCoordinate, route: route)
        if dist > 70 {
            offRouteTicksForReroute += 1
        } else {
            offRouteTicksForReroute = 0
            return
        }

        guard offRouteTicksForReroute >= 5 else { return }
        if let last = lastRerouteAt, Date().timeIntervalSince(last) < 12 { return }
        guard rerouteTask == nil else { return }

        lastRerouteAt = Date()
        offRouteTicksForReroute = 0
        let lat = userCoordinate.latitude
        let lon = userCoordinate.longitude
        let destLat = dest.latitude
        let destLon = dest.longitude
        let destTitle = title

        rerouteTask = Task { @MainActor in
            defer { rerouteTask = nil }
            do {
                _ = try await MapKitNavigationService.shared.planBestRoute(
                    toLatitude: destLat,
                    toLongitude: destLon,
                    destinationName: destTitle,
                    fromLatitude: lat,
                    fromLongitude: lon,
                    animateReveal: false,
                    resetTripStats: false
                )
            } catch {
                // Ciche niepowodzenie — spróbujemy przy kolejnym zjeździe.
            }
        }
    }

    /// Scoring alternatyw przy głosowej zmianie manewru.
    static func buildManeuversForPreference(from route: MKRoute) -> [TurnManeuver] {
        buildManeuvers(from: route)
    }

    private static func buildManeuvers(from route: MKRoute?) -> [TurnManeuver] {
        guard let route else { return [] }
        var result: [TurnManeuver] = []
        var previousPoints: [CLLocationCoordinate2D] = []

        for step in route.steps {
            let rawText = step.instructions
            let text = normalizeInstruction(rawText)

            let line = step.polyline
            guard line.pointCount > 0 else {
                previousPoints = []
                continue
            }
            var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: line.pointCount)
            line.getCoordinates(&points, range: NSRange(location: 0, length: line.pointCount))
            guard let first = points.first else {
                previousPoints = []
                continue
            }

            // Kąt skrętu jak na mapie: dojazd (koniec poprzedniego kroku) → wyjazd (początek tego).
            let incoming = bearingAlong(points: previousPoints, fromEnd: true, meters: 35)
                ?? bearingAlong(points: previousPoints, fromEnd: true, meters: 12)
            let outgoing = bearingAlong(points: points, fromEnd: false, meters: 35)
                ?? bearingAlong(points: points, fromEnd: false, meters: 12)
            let startHeading = outgoing
                ?? (points.count >= 2 ? bearing(from: points[0], to: points[min(1, points.count - 1)]) : 0)

            let direction = classifyDirection(
                text,
                incomingBearing: incoming,
                outgoingBearing: outgoing
            )

            let looksLikeTurn = direction == .left || direction == .right
                || text.contains("skrec") || text.contains("turn")
                || text.contains("zjedz") || text.contains("zjazd")
                || text.contains("rondo")
            defer { previousPoints = points }

            guard looksLikeTurn, step.distance > 5 else { continue }
            guard direction == .left || direction == .right else { continue }

            result.append(
                TurnManeuver(
                    id: UUID(),
                    coordinate: first,
                    heading: startHeading,
                    instruction: rawText,
                    direction: direction,
                    stepDistance: step.distance
                )
            )
        }
        return result
    }

    /// Geometria trasy wygrywa przy wyraźnym skręcie (to widać na mapie);
    /// tekst MapKit tylko gdy kąt jest niejednoznaczny.
    private static func classifyDirection(
        _ text: String,
        incomingBearing: CLLocationDirection?,
        outgoingBearing: CLLocationDirection?
    ) -> TurnDirection {
        let fromText = classifyDirectionFromText(text)
        let fromGeometry: TurnDirection? = {
            guard let incoming = incomingBearing, let outgoing = outgoingBearing else { return nil }
            let delta = signedHeadingDelta(from: incoming, to: outgoing)
            // Dodatni delta = heading rośnie zgodnie z zegarem = skręt w prawo.
            if abs(delta) >= 25 {
                return delta > 0 ? .right : .left
            }
            if abs(delta) < 12 {
                return .straight
            }
            return nil
        }()

        if let geo = fromGeometry, geo == .left || geo == .right {
            // Przy konflikcie tekst↔mapa zaufaj geometrii (kafelek = to co widać na trasie).
            if let textDir = fromText, textDir != geo, textDir != .straight {
                return geo
            }
            return geo
        }
        if let textDir = fromText {
            return textDir
        }
        if text.contains("prosto") || text.contains("straight") || text.contains("kontynuuj") {
            return .straight
        }
        return .straight
    }

    private static func normalizeInstruction(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "l")
    }

    private static func classifyDirectionFromText(_ text: String) -> TurnDirection? {
        // text już znormalizowany (bez diakrytyków)
        let cues: [(String, TurnDirection)] = [
            ("skrec w prawo", .right), ("skrec w lewo", .left),
            ("zjedz w prawo", .right), ("zjedz w lewo", .left),
            ("turn right", .right), ("turn left", .left),
            ("keep right", .right), ("keep left", .left),
            ("bear right", .right), ("bear left", .left),
            ("trzymaj sie prawej", .right), ("trzymaj sie lewej", .left),
            ("na prawo", .right), ("na lewo", .left),
            (" w prawo", .right), (" w lewo", .left)
        ]
        var bestIndex = -1
        var bestDirection: TurnDirection?
        for (phrase, direction) in cues {
            var searchStart = text.startIndex
            while let range = text.range(of: phrase, range: searchStart..<text.endIndex) {
                let idx = text.distance(from: text.startIndex, to: range.lowerBound)
                if idx >= bestIndex {
                    bestIndex = idx
                    bestDirection = direction
                }
                searchStart = range.upperBound
            }
        }
        return bestDirection
    }

    /// Heading po ~`meters` metrach od początku (lub końca) polilinii kroku.
    private static func bearingAlong(
        points: [CLLocationCoordinate2D],
        fromEnd: Bool,
        meters: CLLocationDistance
    ) -> CLLocationDirection? {
        guard points.count >= 2 else { return nil }
        if fromEnd {
            var remaining = meters
            var idx = points.count - 1
            while idx > 0 {
                let a = points[idx - 1]
                let b = points[idx]
                let seg = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                if seg >= remaining || idx == 1 {
                    return bearing(from: a, to: b)
                }
                remaining -= seg
                idx -= 1
            }
            return bearing(from: points[points.count - 2], to: points[points.count - 1])
        }

        var remaining = meters
        var idx = 0
        while idx < points.count - 1 {
            let a = points[idx]
            let b = points[idx + 1]
            let seg = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if seg >= remaining || idx == points.count - 2 {
                return bearing(from: a, to: b)
            }
            remaining -= seg
            idx += 1
        }
        return bearing(from: points[0], to: points[1])
    }

    /// Znormalizowana różnica headingów w (−180, 180]; dodatnia = w prawo.
    private static func signedHeadingDelta(from: CLLocationDirection, to: CLLocationDirection) -> Double {
        signedHeadingDeltaPublic(from: from, to: to)
    }

    static func signedHeadingDeltaPublic(from: CLLocationDirection, to: CLLocationDirection) -> Double {
        var d = to - from
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
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

    /// Aktualny tryb z ustawień (samochód domyślnie).
    static var activeTravelMode: TravelMode {
        TravelMode(rawValue: UserDefaults.standard.string(forKey: "travelMode") ?? "") ?? .car
    }

    private var activeTravelMode: TravelMode { Self.activeTravelMode }

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

    /// Najbliższy sklep / sieć (Żabka, Lewiatan, Empik…).
    func findNearestStore(
        query: String,
        near coordinate: CLLocationCoordinate2D
    ) async throws -> (place: PlaceResult, mapItem: MKMapItem)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .store, .pharmacy, .bakery, .foodMarket, .cafe
        ])
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 12_000,
            longitudinalMeters: 12_000
        )
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let q = query.lowercased()
        let ranked = response.mapItems.compactMap { item -> (PlaceResult, MKMapItem, CLLocationDistance, Int)? in
            guard let place = Self.mapItemToPlace(item, fallbackName: query) else { return nil }
            let d = origin.distance(
                from: CLLocation(latitude: place.latitude, longitude: place.longitude)
            )
            let name = (item.name ?? "").lowercased()
            // Preferuj trafienia z nazwą marki w tytule.
            let nameBonus = name.contains(q) || q.split(separator: " ").contains(where: { name.contains($0) })
                ? 0 : 1
            return (place, item, d, nameBonus)
        }
        .sorted {
            if $0.3 != $1.3 { return $0.3 < $1.3 }
            return $0.2 < $1.2
        }

        guard let best = ranked.first else {
            // Fallback bez filtra POI — czasem sieci są skategoryzowane inaczej.
            let loose = MKLocalSearch.Request()
            loose.naturalLanguageQuery = query
            loose.resultTypes = [.pointOfInterest, .address]
            loose.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 15_000,
                longitudinalMeters: 15_000
            )
            let looseResponse = try await MKLocalSearch(request: loose).start()
            let looseRanked = looseResponse.mapItems.compactMap { item -> (PlaceResult, MKMapItem, CLLocationDistance)? in
                guard let place = Self.mapItemToPlace(item, fallbackName: query) else { return nil }
                let d = origin.distance(
                    from: CLLocation(latitude: place.latitude, longitude: place.longitude)
                )
                return (place, item, d)
            }
            .sorted { $0.2 < $1.2 }
            guard let hit = looseRanked.first else { return nil }
            return (hit.0, hit.1)
        }
        return (best.0, best.1)
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
        // Bez mini-mapki przy szukaniu celu nawigacji — tylko wynik tekstowy.
        return response.mapItems.lazy.compactMap { Self.mapItemToPlace($0, fallbackName: query) }.first
    }

    private static func mapItemToPlace(_ item: MKMapItem, fallbackName: String) -> PlaceResult? {
        let coord = MapKitCompatibility.coordinate(of: item)
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
        fromLongitude: Double? = nil,
        animateReveal: Bool = true,
        resetTripStats: Bool = true
    ) async throws -> (best: RouteResult, alternates: [RouteResult]) {
        guard NavigationEULA.isAccepted else {
            throw NavigationError.disclaimerRequired
        }

        let destCoord = CLLocationCoordinate2D(latitude: toLatitude, longitude: toLongitude)
        let destination = MapKitCompatibility.mapItem(coordinate: destCoord, name: destinationName)

        let source: MKMapItem
        if let fromLatitude, let fromLongitude {
            source = MapKitCompatibility.mapItem(
                coordinate: CLLocationCoordinate2D(latitude: fromLatitude, longitude: fromLongitude),
                name: "Start"
            )
        } else if let from = location?.coordinate {
            source = MapKitCompatibility.mapItem(coordinate: from, name: nil)
        } else {
            source = .forCurrentLocation()
        }

        let travelMode = Self.activeTravelMode
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        // Rower: ścieżki / trasy piesze (najbliższy odpowiednik roweru w MapKit).
        request.transportType = travelMode.mapKitTransportType

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
                name: route.name.isEmpty ? travelMode.routeLabel : route.name,
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
            alternates: [],
            animateReveal: animateReveal,
            resetTripStats: resetTripStats
        )

        let bestResult = mappedRoutes.first(where: {
            abs($0.distanceMeters - best.distance) < 1
                && abs($0.expectedSeconds - best.expectedTravelTime) < 1
        }) ?? RouteResult(
            name: best.name.isEmpty ? travelMode.routeLabel : best.name,
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

    /// Głos: „chcę jechać prosto / w lewo na następnym skrzyżowaniu” — przelicz trasę pod ten manewr.
    /// Mówi „zmieniłem” TYLKO gdy mapa dostaje inną polilinię i da się potem dojechać do celu.
    func reroutePreferringManeuver(_ direction: TurnDirection) async -> String {
        guard let mapState, mapState.isNavigating else {
            return "Nie mam aktywnej trasy — najpierw wybierz cel."
        }
        guard let dest = mapState.destinationCoordinate,
              let title = mapState.destinationTitle,
              let user = location?.coordinate else {
            return "Potrzebuję lokalizacji i aktywnego celu, żeby zmienić trasę."
        }

        let currentRoute = mapState.route
        let snap = mapState.nextManeuverSnapshot(userCoordinate: user)
        if let planned = snap?.maneuver.direction, planned == direction {
            return "Już mam w planie jazdę \(direction.spoken) na następnym skrzyżowaniu — trzymaj się trasy."
        }

        let intersection: CLLocationCoordinate2D
        let approach: CLLocationDirection
        if let snap {
            intersection = snap.maneuver.coordinate
            // Heading dojazdu z trasy (nie „z GPS do pinu”) — pewniejszy kąt manewru.
            if let route = currentRoute,
               let along = Self.pointAlongRoute(route, near: intersection, metersAhead: -40)
                ?? Self.pointAlongRoute(route, near: user, metersAhead: 40) {
                approach = along.bearing
            } else {
                approach = Self.bearing(from: user, to: intersection)
            }
        } else if let route = currentRoute,
                  let ahead = Self.pointAlongRoute(route, near: user, metersAhead: 120) {
            intersection = ahead.coordinate
            approach = ahead.bearing
        } else {
            intersection = Self.offsetCoordinate(user, bearing: 0, meters: 100)
            approach = 0
        }

        let exitBearing = Self.exitBearing(approach: approach, direction: direction)
        let vias = Self.viaCandidates(from: intersection, exitBearing: exitBearing)
        let transport = Self.activeTravelMode.mapKitTransportType

        do {
            // 1) Pełne alternatywy do celu — muszą być INNE niż obecna i wychodzić wybranym kierunkiem.
            if let alt = try await Self.findDistinctAlternate(
                from: user,
                to: dest,
                current: currentRoute,
                intersection: intersection,
                approach: approach,
                want: direction,
                vias: vias,
                transportType: transport
            ) {
                mapState.presentDestination(
                    coordinate: dest,
                    title: title,
                    route: alt,
                    alternates: [],
                    animateReveal: true,
                    resetTripStats: false
                )
                Self.rememberManeuverPreference(
                    via: vias.first ?? intersection,
                    destination: dest,
                    title: title,
                    avoidedHint: snap?.maneuver.instruction
                )
                let minutes = Int((alt.expectedTravelTime / 60).rounded())
                return "Zmieniłem trasę — na następnym skrzyżowaniu jedź \(direction.spoken). Do \(title) ok. \(minutes) min."
            }

            // 2) Szukaj korytarza (via) z dowodem dojazdu, potem TYLKO pełna trasa user→cel.
            //    Nigdy nie podstawiamy odcinka do via jako celu — pin i koniec linii = oryginalny dest.
            if let full = try await Self.findFullRouteAfterPreferredExit(
                from: user,
                to: dest,
                current: currentRoute,
                intersection: intersection,
                approach: approach,
                want: direction,
                vias: vias,
                transportType: transport
            ) {
                mapState.presentDestination(
                    coordinate: dest,
                    title: title,
                    route: full,
                    alternates: [],
                    animateReveal: true,
                    resetTripStats: false
                )
                if let tip = RouteGeometry.coordinate(along: full.polyline, progress: 0.2) {
                    Self.rememberManeuverPreference(
                        via: tip,
                        destination: dest,
                        title: title,
                        avoidedHint: snap?.maneuver.instruction
                    )
                }
                let minutes = Int((full.expectedTravelTime / 60).rounded())
                return "Zmieniłem trasę — na następnym skrzyżowaniu jedź \(direction.spoken). Do \(title) ok. \(minutes) min."
            }

            // 3) Soft: najlepsza alternatywa z wyjściem najbliższym żądanemu (luźniejszy próg kąta).
            if let soft = try await Self.findSoftAlternate(
                from: user,
                to: dest,
                current: currentRoute,
                intersection: intersection,
                approach: approach,
                want: direction,
                transportType: transport
            ) {
                mapState.presentDestination(
                    coordinate: dest,
                    title: title,
                    route: soft,
                    alternates: [],
                    animateReveal: true,
                    resetTripStats: false
                )
                Self.rememberManeuverPreference(
                    via: vias.first ?? intersection,
                    destination: dest,
                    title: title,
                    avoidedHint: snap?.maneuver.instruction
                )
                let minutes = Int((soft.expectedTravelTime / 60).rounded())
                return "Zmieniłem trasę — na następnym skrzyżowaniu jedź \(direction.spoken). Do \(title) ok. \(minutes) min."
            }

            // 4) Preferencja + planBestRoute — jeśli mapa się zmieniła i cel jest ten sam, AKCEPTUJ.
            //    Wcześniej zbyt ostry filtr kąta odrzucał trasy, które po „odnowieniu” i tak działały.
            Self.rememberManeuverPreference(
                via: vias.first ?? intersection,
                destination: dest,
                title: title,
                avoidedHint: snap?.maneuver.instruction
            )
            let before = currentRoute
            _ = try await planBestRoute(
                toLatitude: dest.latitude,
                toLongitude: dest.longitude,
                destinationName: title,
                fromLatitude: user.latitude,
                fromLongitude: user.longitude,
                animateReveal: true,
                resetTripStats: false
            )
            if let after = mapState.route,
               Self.routeEndsNear(after, destination: dest),
               !Self.routesVisuallySimilar(after, before) {
                let minutes = Int((after.expectedTravelTime / 60).rounded())
                return "Zmieniłem trasę — na następnym skrzyżowaniu jedź \(direction.spoken). Do \(title) ok. \(minutes) min."
            }
            // Ta sama trasa co przedtem → naprawdę brak alternatywy.
            if let before, Self.routesVisuallySimilar(mapState.route, before) {
                mapState.presentDestination(
                    coordinate: dest,
                    title: title,
                    route: before,
                    alternates: [],
                    animateReveal: false,
                    resetTripStats: false
                )
            }

            return "Sprawdziłem możliwe trasy — po jeździe \(direction.spoken) na tym skrzyżowaniu nie da się sensownie dojechać do \(title). Zostajemy przy obecnej trasie."
        } catch {
            return "Nie udało się sprawdzić innej trasy: \(error.localizedDescription)"
        }
    }

    private static func exitBearing(approach: CLLocationDirection, direction: TurnDirection) -> CLLocationDirection {
        switch direction {
        case .straight: return approach
        case .left: return (approach - 90 + 360).truncatingRemainder(dividingBy: 360)
        case .right: return (approach + 90).truncatingRemainder(dividingBy: 360)
        }
    }

    private static func viaCandidates(
        from intersection: CLLocationCoordinate2D,
        exitBearing: CLLocationDirection
    ) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        // Najpierw „na wprost” wyjścia, potem lekkie odchyłki (droga rzadko leży dokładnie pod kątem).
        for meters in [120.0, 170.0, 230.0] {
            for delta in [0.0, -22.0, 22.0, -40.0, 40.0] {
                let b = (exitBearing + delta + 360).truncatingRemainder(dividingBy: 360)
                result.append(offsetCoordinate(intersection, bearing: b, meters: meters))
            }
        }
        return result
    }

    private static func findDistinctAlternate(
        from user: CLLocationCoordinate2D,
        to dest: CLLocationCoordinate2D,
        current: MKRoute?,
        intersection: CLLocationCoordinate2D,
        approach: CLLocationDirection,
        want: TurnDirection,
        vias: [CLLocationCoordinate2D],
        transportType: MKDirectionsTransportType
    ) async throws -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MapKitCompatibility.mapItem(coordinate: user, name: nil)
        request.destination = MapKitCompatibility.mapItem(coordinate: dest, name: "Cel")
        request.transportType = transportType
        request.requestsAlternateRoutes = true
        let response = try await MKDirections(request: request).calculate()

        var ranked: [(MKRoute, Double)] = []
        for route in response.routes {
            if routesVisuallySimilar(route, current) { continue }
            // Koniec = prawdziwy cel (nie via / nie skrzyżowanie).
            guard let routeEnd = RouteGeometry.coordinate(along: route.polyline, progress: 1) else { continue }
            let endToDest = CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)
                .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
            guard endToDest < 120 else { continue }

            guard routeExitsInDirection(
                route,
                intersection: intersection,
                approach: approach,
                want: want
            ) else { continue }

            let viaBonus = vias.map { polylineMinDistance(route.polyline, to: $0) }.min() ?? 500
            let score = route.expectedTravelTime / 60 + viaBonus / 80
            ranked.append((route, score))
        }
        return ranked.min(by: { $0.1 < $1.1 })?.0
    }

    /// Znajdź korytarz z preferowanym wyjazdem, potwierdź dojazd do celu, zwróć pełną trasę user→cel.
    private static func findFullRouteAfterPreferredExit(
        from user: CLLocationCoordinate2D,
        to dest: CLLocationCoordinate2D,
        current: MKRoute?,
        intersection: CLLocationCoordinate2D,
        approach: CLLocationDirection,
        want: TurnDirection,
        vias: [CLLocationCoordinate2D],
        transportType: MKDirectionsTransportType
    ) async throws -> MKRoute? {
        // Cache alternatyw do prawdziwego celu — zawsze kończą się na `dest`.
        let destReq = MKDirections.Request()
        destReq.source = MapKitCompatibility.mapItem(coordinate: user, name: nil)
        destReq.destination = MapKitCompatibility.mapItem(coordinate: dest, name: "Cel")
        destReq.transportType = transportType
        destReq.requestsAlternateRoutes = true
        let destAlternates = (try? await MKDirections(request: destReq).calculate().routes) ?? []

        var corridorSamples: [[CLLocationCoordinate2D]] = []
        var checked = 0

        let ordered = vias.enumerated().sorted { a, b in
            let aMain = a.offset % 5 == 0
            let bMain = b.offset % 5 == 0
            if aMain != bMain { return aMain }
            return a.offset < b.offset
        }.map(\.element)

        for via in ordered {
            if checked >= 8 { break }

            let toViaReq = MKDirections.Request()
            toViaReq.source = MapKitCompatibility.mapItem(coordinate: user, name: nil)
            toViaReq.destination = MapKitCompatibility.mapItem(coordinate: via, name: "Via")
            toViaReq.transportType = transportType
            toViaReq.requestsAlternateRoutes = true

            guard let toViaRoutes = try? await MKDirections(request: toViaReq).calculate().routes,
                  !toViaRoutes.isEmpty else { continue }

            for leg1 in toViaRoutes.prefix(2) {
                if routesVisuallySimilar(leg1, current) { continue }
                guard routeExitsInDirection(
                    leg1,
                    intersection: intersection,
                    approach: approach,
                    want: want
                ) else { continue }

                // Punkt na prawdziwej drodze (po skrzyżowaniu), nie surowy offset GPS.
                guard let roadVia = coordinateOnRoute(leg1, afterPassing: intersection, metersPast: 70)
                        ?? RouteGeometry.coordinate(along: leg1.polyline, progress: 0.65)
                else { continue }

                checked += 1
                // Dowód: z korytarza da się dojechać do ORYGINALNEGO celu.
                let toDestReq = MKDirections.Request()
                toDestReq.source = MapKitCompatibility.mapItem(coordinate: roadVia, name: "Via")
                toDestReq.destination = MapKitCompatibility.mapItem(coordinate: dest, name: "Cel")
                toDestReq.transportType = transportType
                toDestReq.requestsAlternateRoutes = false
                guard (try? await MKDirections(request: toDestReq).calculate().routes.first) != nil
                else { continue }

                corridorSamples.append(samplePolyline(leg1.polyline, maxSamples: 14))

                // Pełna trasa do celu pasująca do korytarza.
                if let match = bestFullRoute(
                    among: destAlternates,
                    current: current,
                    intersection: intersection,
                    approach: approach,
                    want: want,
                    corridorSamples: corridorSamples,
                    roadVia: roadVia,
                    destination: dest
                ) {
                    return match
                }
            }
        }

        // Ostatnia szansa: spośród alternatyw do celu wybierz najlepszy korytarz (jeśli coś zebraliśmy).
        if !corridorSamples.isEmpty, !destAlternates.isEmpty {
            return bestFullRoute(
                among: destAlternates,
                current: current,
                intersection: intersection,
                approach: approach,
                want: want,
                corridorSamples: corridorSamples,
                roadVia: corridorSamples[0].last ?? intersection,
                destination: dest
            )
        }
        return nil
    }

    private static func bestFullRoute(
        among routes: [MKRoute],
        current: MKRoute?,
        intersection: CLLocationCoordinate2D,
        approach: CLLocationDirection,
        want: TurnDirection,
        corridorSamples: [[CLLocationCoordinate2D]],
        roadVia: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D? = nil
    ) -> MKRoute? {
        var ranked: [(MKRoute, Double)] = []
        for route in routes {
            if routesVisuallySimilar(route, current) { continue }
            // Koniec polilinii = oryginalny cel (nigdy punkt via).
            guard let routeEnd = RouteGeometry.coordinate(along: route.polyline, progress: 1) else { continue }
            if let destination {
                let toDest = CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)
                    .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
                guard toDest < 120 else { continue }
            }
            let endToVia = CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)
                .distance(from: CLLocation(latitude: roadVia.latitude, longitude: roadVia.longitude))
            // Odrzuć trasę, która „kończy się” przy via zamiast przy celu.
            guard endToVia > 200 else { continue }

            guard routeExitsInDirection(
                route,
                intersection: intersection,
                approach: approach,
                want: want
            ) else { continue }

            let viaNear = polylineMinDistance(route.polyline, to: roadVia)
            // Luźniej — drogi rzadko leżą dokładnie pod offsetem via.
            guard viaNear < 260 else { continue }

            var overlap: Double = 0
            if let samples = corridorSamples.max(by: { $0.count < $1.count }), samples.count >= 2 {
                overlap = pathOverlapScore(route: route, samples: samples)
            }
            let score = viaNear / 50 - overlap * 30 + route.expectedTravelTime / 90
            ranked.append((route, score))
        }
        return ranked.min(by: { $0.1 < $1.1 })?.0
    }

    /// Alternatywa z wyjściem „wystarczająco blisko” żądanego kierunku (nie idealnie).
    private static func findSoftAlternate(
        from user: CLLocationCoordinate2D,
        to dest: CLLocationCoordinate2D,
        current: MKRoute?,
        intersection: CLLocationCoordinate2D,
        approach: CLLocationDirection,
        want: TurnDirection,
        transportType: MKDirectionsTransportType
    ) async throws -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MapKitCompatibility.mapItem(coordinate: user, name: nil)
        request.destination = MapKitCompatibility.mapItem(coordinate: dest, name: "Cel")
        request.transportType = transportType
        request.requestsAlternateRoutes = true
        let routes = try await MKDirections(request: request).calculate().routes

        var ranked: [(MKRoute, Double)] = []
        for route in routes {
            if routesVisuallySimilar(route, current) { continue }
            guard routeEndsNear(route, destination: dest) else { continue }
            let err = exitAngleError(route, intersection: intersection, approach: approach, want: want)
            guard err < 85 else { continue }
            // Odrzuć tylko wyraźnie przeciwny kierunek.
            if let exit = exitBearingNearIntersection(route.polyline, intersection: intersection) {
                let delta = NavigationMapState.signedHeadingDeltaPublic(from: approach, to: exit)
                if want == .left, delta > 35 { continue }
                if want == .right, delta < -35 { continue }
                if want == .straight, abs(delta) > 70 { continue }
            }
            ranked.append((route, err + route.expectedTravelTime / 120))
        }
        return ranked.min(by: { $0.1 < $1.1 })?.0
    }

    private static func routeEndsNear(_ route: MKRoute, destination: CLLocationCoordinate2D) -> Bool {
        guard let end = RouteGeometry.coordinate(along: route.polyline, progress: 1) else { return false }
        return CLLocation(latitude: end.latitude, longitude: end.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)) < 140
    }

    /// 0 = idealny wyjazd; duże wartości = zły kierunek.
    private static func exitAngleError(
        _ route: MKRoute,
        intersection: CLLocationCoordinate2D,
        approach: CLLocationDirection,
        want: TurnDirection
    ) -> Double {
        let wantBearing = exitBearing(approach: approach, direction: want)
        guard let exit = exitBearingNearIntersection(route.polyline, intersection: intersection) else {
            let first = NavigationMapState.buildManeuversForPreference(from: route).first?.direction
            if first == want { return 8 }
            if want == .straight, first == nil { return 20 }
            return 90
        }
        let delta = abs(NavigationMapState.signedHeadingDeltaPublic(from: wantBearing, to: exit))
        return delta
    }

    private static func coordinateOnRoute(
        _ route: MKRoute,
        afterPassing junction: CLLocationCoordinate2D,
        metersPast: CLLocationDistance
    ) -> CLLocationCoordinate2D? {
        let poly = route.polyline
        let count = poly.pointCount
        guard count >= 2 else { return nil }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        let target = CLLocation(latitude: junction.latitude, longitude: junction.longitude)
        var bestIdx = 0
        var bestD = CLLocationDistance.greatestFiniteMagnitude
        for i in 0..<count {
            let d = target.distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
            if d < bestD {
                bestD = d
                bestIdx = i
            }
        }
        guard bestD < 180 else { return nil }
        var remaining = metersPast
        var idx = bestIdx
        while idx < count - 1 {
            let a = coords[idx]
            let b = coords[idx + 1]
            let seg = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if seg >= remaining {
                let t = remaining / max(seg, 1)
                return CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
            }
            remaining -= seg
            idx += 1
        }
        return coords.last
    }

    private static func samplePolyline(_ polyline: MKPolyline, maxSamples: Int) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        if count <= maxSamples { return coords }
        var result: [CLLocationCoordinate2D] = []
        for i in 0..<maxSamples {
            let idx = Int(Double(i) / Double(maxSamples - 1) * Double(count - 1))
            result.append(coords[idx])
        }
        return result
    }

    /// Czy polilinia za skrzyżowaniem wychodzi w żądanym kierunku względem dojazdu.
    private static func routeExitsInDirection(
        _ route: MKRoute,
        intersection: CLLocationCoordinate2D,
        approach: CLLocationDirection,
        want: TurnDirection
    ) -> Bool {
        guard let exit = exitBearingNearIntersection(route.polyline, intersection: intersection) else {
            // Brak geometrii przy skrzyżowaniu — fallback na pierwszy manewr z instrukcji.
            let first = NavigationMapState.buildManeuversForPreference(from: route).first?.direction
            if want == .straight { return first == nil || first == .straight }
            return first == want
        }
        let delta = NavigationMapState.signedHeadingDeltaPublic(from: approach, to: exit)
        // Luźniejsze progi — miejskie skrzyżowania rzadko mają idealne 90°.
        switch want {
        case .straight:
            return abs(delta) < 38
        case .left:
            return delta < -16 && delta > -160
        case .right:
            return delta > 16 && delta < 160
        }
    }

    private static func exitBearingNearIntersection(
        _ polyline: MKPolyline,
        intersection: CLLocationCoordinate2D
    ) -> CLLocationDirection? {
        let count = polyline.pointCount
        guard count >= 2 else { return nil }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        let target = CLLocation(latitude: intersection.latitude, longitude: intersection.longitude)
        var bestIdx = 0
        var bestD = CLLocationDistance.greatestFiniteMagnitude
        for i in 0..<count {
            let d = target.distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
            if d < bestD {
                bestD = d
                bestIdx = i
            }
        }
        guard bestD < 220 else { return nil }
        // Weź punkt ~40–80 m ZA najbliższym punktem skrzyżowania.
        var remaining: CLLocationDistance = 55
        var idx = bestIdx
        while idx < count - 1 {
            let a = coords[idx]
            let b = coords[idx + 1]
            let seg = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if seg >= remaining {
                return bearing(from: a, to: b)
            }
            remaining -= seg
            idx += 1
        }
        if bestIdx + 1 < count {
            return bearing(from: coords[bestIdx], to: coords[min(bestIdx + 1, count - 1)])
        }
        return nil
    }

    private static func routesVisuallySimilar(_ a: MKRoute?, _ b: MKRoute?) -> Bool {
        guard let a, let b else { return false }
        if abs(a.distance - b.distance) < 40,
           abs(a.expectedTravelTime - b.expectedTravelTime) < 20 {
            // Porównaj środek i koniec polilinii.
            let midA = RouteGeometry.coordinate(along: a.polyline, progress: 0.35)
            let midB = RouteGeometry.coordinate(along: b.polyline, progress: 0.35)
            let endA = RouteGeometry.coordinate(along: a.polyline, progress: 0.85)
            let endB = RouteGeometry.coordinate(along: b.polyline, progress: 0.85)
            if let midA, let midB, let endA, let endB {
                let d1 = CLLocation(latitude: midA.latitude, longitude: midA.longitude)
                    .distance(from: CLLocation(latitude: midB.latitude, longitude: midB.longitude))
                let d2 = CLLocation(latitude: endA.latitude, longitude: endA.longitude)
                    .distance(from: CLLocation(latitude: endB.latitude, longitude: endB.longitude))
                if d1 < 70, d2 < 90 { return true }
            }
        }
        return false
    }

    private static func polylineMinDistance(_ polyline: MKPolyline, to point: CLLocationCoordinate2D) -> CLLocationDistance {
        let count = polyline.pointCount
        guard count > 0 else { return .greatestFiniteMagnitude }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        let target = CLLocation(latitude: point.latitude, longitude: point.longitude)
        var minD = CLLocationDistance.greatestFiniteMagnitude
        // Co kilka punktów — wystarczy do scoringu.
        let step = max(1, count / 40)
        var i = 0
        while i < count {
            let d = target.distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
            if d < minD { minD = d }
            i += step
        }
        return minD
    }

    /// `metersAhead` ujemne = cofnij się wzdłuż trasy (np. dojazd przed skrzyżowaniem).
    private static func pointAlongRoute(
        _ route: MKRoute,
        near user: CLLocationCoordinate2D,
        metersAhead: CLLocationDistance
    ) -> (coordinate: CLLocationCoordinate2D, bearing: CLLocationDirection)? {
        let poly = route.polyline
        let count = poly.pointCount
        guard count >= 2 else { return nil }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
        var bestIdx = 0
        var bestD = CLLocationDistance.greatestFiniteMagnitude
        for i in 0..<count {
            let d = userLoc.distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
            if d < bestD {
                bestD = d
                bestIdx = i
            }
        }

        if metersAhead < 0 {
            var remaining = -metersAhead
            var idx = bestIdx
            while idx > 0 {
                let a = coords[idx - 1]
                let b = coords[idx]
                let seg = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                if seg >= remaining {
                    let t = remaining / max(seg, 1)
                    let coord = CLLocationCoordinate2D(
                        latitude: b.latitude + (a.latitude - b.latitude) * t,
                        longitude: b.longitude + (a.longitude - b.longitude) * t
                    )
                    return (coord, bearing(from: a, to: b))
                }
                remaining -= seg
                idx -= 1
            }
            return (coords[0], bearing(from: coords[0], to: coords[1]))
        }

        var remaining = metersAhead
        var idx = bestIdx
        while idx < count - 1 {
            let a = coords[idx]
            let b = coords[idx + 1]
            let seg = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if seg >= remaining {
                let t = remaining / max(seg, 1)
                let coord = CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
                return (coord, bearing(from: a, to: b))
            }
            remaining -= seg
            idx += 1
        }
        let last = coords[count - 1]
        let prev = coords[count - 2]
        return (last, bearing(from: prev, to: last))
    }

    private static func offsetCoordinate(
        _ from: CLLocationCoordinate2D,
        bearing: CLLocationDirection,
        meters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let R = 6_378_137.0
        let brng = bearing * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(meters / R) + cos(lat1) * sin(meters / R) * cos(brng))
        let lon2 = lon1 + atan2(
            sin(brng) * sin(meters / R) * cos(lat1),
            cos(meters / R) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
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

    private static func rememberManeuverPreference(
        via: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        title: String,
        avoidedHint: String?
    ) {
        DriveMateMemoryStore.shared.recordSpokenManeuverPreference(
            destinationTitle: title,
            destination: destination,
            via: via,
            avoidedStreetHint: avoidedHint
        )
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
        request.transportType = Self.activeTravelMode.mapKitTransportType
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

    /// Analiza korków na aktywnej trasie: ETA MapKit + godzina + próbki odcinków.
    func analyzeActiveRouteTrafficRisk(focusHint: String? = nil) async -> String {
        guard let mapState, mapState.isNavigating,
              let route = mapState.route,
              let dest = mapState.destinationCoordinate,
              let title = mapState.destinationTitle,
              let user = location?.coordinate else {
            if let here = location?.coordinate {
                return (try? await trafficSnapshot(near: here))
                    ?? "Nie mam aktywnej trasy — włącz nawigację, a ocenię korki po drodze."
            }
            return "Nie mam lokalizacji ani trasy do oceny korków."
        }

        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now) // 1 = niedziela
        let isWeekday = weekday >= 2 && weekday <= 6
        let morningRush = isWeekday && hour >= 7 && hour <= 9
        let eveningRush = isWeekday && hour >= 15 && hour <= 18
        let isRush = morningRush || eveningRush
        let isNight = hour >= 22 || hour < 6
        let isWeekend = weekday == 1 || weekday == 7

        let etaSec = route.expectedTravelTime
        let distanceM = route.distance
        // Freeflow miejski ~42 km/h; poza miastem dłuższe trasy ~55 km/h.
        let freeflowMps = distanceM > 12_000 ? 15.3 : 11.7
        let freeflowSec = distanceM / freeflowMps
        let delayRatio = etaSec / max(freeflowSec, 60)
        let delayMin = max(0, Int(((etaSec - freeflowSec) / 60).rounded()))
        let etaMin = Int((etaSec / 60).rounded())
        let notices = route.advisoryNotices
        let avgKmh = (distanceM / 1000) / max(etaSec / 3600, 0.01)

        // Próbki 2–3 odcinków wzdłuż trasy (środek / ¾) — lokalne spowolnienia.
        var segmentFlags: [String] = []
        let sampleProgress: [CGFloat] = distanceM > 4_000 ? [0.35, 0.65, 0.85] : [0.5, 0.8]
        for (idx, p) in sampleProgress.enumerated() {
            guard let point = RouteGeometry.coordinate(along: route.polyline, progress: p) else { continue }
            let prevProgress = idx == 0 ? 0.08 : sampleProgress[idx - 1]
            guard let from = RouteGeometry.coordinate(along: route.polyline, progress: prevProgress) else { continue }
            if let seg = try? await Self.quickLegStats(from: from, to: point, transport: Self.activeTravelMode.mapKitTransportType) {
                let segFree = seg.distance / freeflowMps
                let segRatio = seg.eta / max(segFree, 30)
                if segRatio >= 1.55 || seg.speedKmh < 16 {
                    segmentFlags.append("w okolicy \(Self.roughProgressLabel(p))")
                } else if segRatio >= 1.28 || seg.speedKmh < 22 {
                    segmentFlags.append("lekko wolniej \(Self.roughProgressLabel(p))")
                }
            }
        }

        enum Risk { case nearZero, low, moderate, high }
        var risk: Risk
        if !notices.isEmpty || delayRatio >= 1.55 || avgKmh < 16 {
            risk = .high
        } else if delayRatio >= 1.28 || avgKmh < 22 || (isRush && delayRatio >= 1.12) {
            risk = .moderate
        } else if isRush || (!segmentFlags.isEmpty && delayRatio >= 1.1) {
            risk = .low
        } else if isNight || (isWeekend && hour >= 10 && hour <= 14) {
            risk = .nearZero
        } else {
            risk = delayRatio < 1.08 ? .nearZero : .low
        }

        // Godzina podbija / obniża werdykt (gdy ETA niepokazuje dużego opóźnienia).
        if risk == .nearZero, isRush { risk = .low }
        if risk == .low, isNight, notices.isEmpty, delayRatio < 1.15 { risk = .nearZero }

        let timeLabel: String = {
            if morningRush { return "to godzina porannego szczytu" }
            if eveningRush { return "to godzina popołudniowego szczytu" }
            if isNight { return "jest noc — ruch zwykle mały" }
            if isWeekend { return "jest weekend" }
            return String(format: "jest godzina %d", hour)
        }()

        var parts: [String] = []
        switch risk {
        case .nearZero:
            parts.append("Na trasie do \(title) szansa na korki jest prawie zerowa.")
            parts.append("\(timeLabel.prefix(1).uppercased())\(timeLabel.dropFirst()), ETA ok. \(etaMin) min — jedzie się raczej płynnie.")
        case .low:
            parts.append("Na trasie do \(title) mała szansa na większe korki.")
            parts.append("\(timeLabel.prefix(1).uppercased())\(timeLabel.dropFirst()); dojazd ok. \(etaMin) min.")
            if delayMin >= 2 {
                parts.append("Ewentualne spowolnienie rzędu \(delayMin) min.")
            }
        case .moderate:
            parts.append("Na trasie do \(title) jest realna szansa na utrudnienia.")
            parts.append("\(timeLabel.prefix(1).uppercased())\(timeLabel.dropFirst()); ETA ok. \(etaMin) min\(delayMin >= 3 ? ", ok. \(delayMin) min powyżej swobodnego ruchu" : "").")
        case .high:
            parts.append("Na trasie do \(title) spodziewaj się korków lub mocnego spowolnienia.")
            parts.append("ETA ok. \(etaMin) min\(delayMin >= 3 ? " — około \(delayMin) min straty względem swobodnego przejazdu" : "").")
        }

        if let focus = focusHint?.trimmingCharacters(in: .whitespacesAndNewlines), focus.count >= 2 {
            parts.append("Pytałeś o okolice „\(focus)” — patrzę na całą trasę, nie tylko ten fragment.")
        }
        let uniqueSeg = Array(Set(segmentFlags)).prefix(2)
        if !uniqueSeg.isEmpty {
            parts.append("Wolniej może być \(uniqueSeg.joined(separator: " i ")).")
        }
        if !notices.isEmpty {
            parts.append("Uwagi MapKit: \(notices.prefix(2).joined(separator: "; ")).")
        }

        // Warstwa ruchu na mapie Apple (compliance) — bez zmiany celu nawigacji.
        MapComplianceStore.shared.showTraffic(
            near: dest,
            title: "Ruch na trasie",
            route: route
        )
        // Przywróć fokus na usera — showTraffic nie powinien „kraść” celu.
        _ = user
        return parts.joined(separator: " ")
    }

    private static func roughProgressLabel(_ p: CGFloat) -> String {
        if p < 0.4 { return "na początku trasy" }
        if p < 0.7 { return "w środkowej części" }
        return "bliżej celu"
    }

    private static func quickLegStats(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transport: MKDirectionsTransportType
    ) async throws -> (distance: CLLocationDistance, eta: TimeInterval, speedKmh: Double) {
        let request = MKDirections.Request()
        request.source = MapKitCompatibility.mapItem(coordinate: from, name: nil)
        request.destination = MapKitCompatibility.mapItem(coordinate: to, name: nil)
        request.transportType = transport
        request.requestsAlternateRoutes = false
        let route = try await MKDirections(request: request).calculate().routes.first
        guard let route else { throw NavigationError.noRoute }
        let kmh = (route.distance / 1000) / max(route.expectedTravelTime / 3600, 0.01)
        return (route.distance, route.expectedTravelTime, kmh)
    }

    /// Ocena ruchu: jedna trasa MKDirections prezentowana na mapie Apple + warstwa ruchu.
    func trafficSnapshot(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 2500
    ) async throws -> String {
        let sourceCoord = location?.coordinate ?? coordinate
        let source = MapKitCompatibility.mapItem(coordinate: sourceCoord, name: nil)
        let dest = MapKitCompatibility.mapItem(coordinate: coordinate, name: "Punkt oceny ruchu")

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

    /// Pozostałe metry wzdłuż polyline od najbliższego punktu do użytkownika aż do końca trasy.
    static func remainingDistanceMeters(
        along polyline: MKPolyline?,
        from userCoordinate: CLLocationCoordinate2D?
    ) -> CLLocationDistance? {
        guard let polyline, polyline.pointCount > 1, let userCoordinate else { return nil }
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        guard coords.count > 1 else { return nil }

        let user = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        var bestIndex = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (index, coord) in coords.enumerated() {
            let d = user.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if d < bestDist {
                bestDist = d
                bestIndex = index
            }
        }

        var remaining: CLLocationDistance = 0
        if bestIndex < coords.count - 1 {
            remaining += user.distance(
                from: CLLocation(latitude: coords[bestIndex].latitude, longitude: coords[bestIndex].longitude)
            )
            for i in bestIndex..<(coords.count - 1) {
                let a = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                let b = CLLocation(latitude: coords[i + 1].latitude, longitude: coords[i + 1].longitude)
                remaining += a.distance(from: b)
            }
        }
        return max(remaining, 0)
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
    /// Drive Mate / odtwarzacz zmienił stan — pokaż panel muzyki.
    static let driveMateDidControlMusic = Notification.Name("driveMateDidControlMusic")
    /// Głosowe / UI wyśrodkowanie — mapa ma natychmiast snapnąć kamerę na użytkownika.
    static let driveMateRecenterRequested = Notification.Name("driveMateRecenterRequested")
}
