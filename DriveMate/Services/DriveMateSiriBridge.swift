import Foundation
import CoreLocation
import MapKit

/// Most Siri / App Intents ↔ nawigacja. Kolejkuje akcje, gdy UI jeszcze nie podpiął `mapState`.
@MainActor
enum DriveMateSiriBridge {
    private enum PendingAction: Equatable {
        case startSaved(placeID: UUID)
        case startQuery(String)
        case endRoute
    }

    private static var pending: PendingAction?
    private static var waiters: [CheckedContinuation<String, Never>] = []

    static func startToSavedPlaceQueued(id: UUID) async -> String {
        await enqueue(.startSaved(placeID: id))
    }

    static func startToDestinationQueued(_ query: String) async -> String {
        await enqueue(.startQuery(query))
    }

    static func endActiveRouteQueued() async -> String {
        await enqueue(.endRoute)
    }

    /// Wywołaj po `assistant.configure` — odpala kolejkę Siri.
    static func flushPendingIfReady() {
        guard MapKitNavigationService.shared.mapState != nil else { return }
        guard let action = pending else {
            // Brak kolejki, ale są waiters (race) — nic nie rób.
            return
        }
        pending = nil
        Task {
            // Siri często odpala intent zanim GPS złapie fix — bez tego MKDirections pada.
            await waitForLocation(timeoutMs: 6_000)
            let reply = await execute(action)
            finishWaiters(with: reply)
        }
    }

    // MARK: - Queue

    private static func enqueue(_ action: PendingAction) async -> String {
        if MapKitNavigationService.shared.mapState != nil {
            await waitForLocation(timeoutMs: 6_000)
            return await execute(action)
        }
        pending = action
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            waiters.append(cont)
        }
    }

    private static func finishWaiters(with reply: String) {
        let list = waiters
        waiters.removeAll()
        for cont in list { cont.resume(returning: reply) }
    }

    private static func execute(_ action: PendingAction) async -> String {
        switch action {
        case .startSaved(let id):
            guard let place = SavedPlacesStore.shared.place(id: id) else {
                return "Nie mam już tego zapisanego miejsca."
            }
            return await startToCoordinate(place)
        case .startQuery(let query):
            return await startToDestinationQuery(query)
        case .endRoute:
            return endActiveRouteNow()
        }
    }

    // MARK: - Navigation

    private static func startToDestinationQuery(_ query: String) async -> String {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return "Podaj cel — na przykład Home, Work, School albo adres."
        }
        // „to my school” / „moja szkoła” → zapisane miejsce (bez MapKit).
        if let saved = SavedPlacesStore.shared.resolve(spokenQuery: cleaned) {
            return await startToCoordinate(saved)
        }
        if SavedPlacesStore.isKnownRoleAlias(cleaned) {
            let label = SavedPlacesStore.canonicalLabel(for: cleaned)
            return "Nie mam jeszcze zapisanego miejsca „\(label)”. W aplikacji powiedz „tutaj jest moja \(label.lowercased())” albo „zapamiętaj moją \(label.lowercased())”."
        }
        let queries = await PlaceNameTranslator.searchQueries(from: cleaned)
        let near = MapKitNavigationService.shared.location?.coordinate
        for candidate in [queries.primary, queries.fallback, cleaned] where !candidate.isEmpty {
            if let place = try? await MapKitNavigationService.shared.findFirstPlace(
                query: candidate,
                near: near
            ) {
                return await startToPlaceResult(place)
            }
        }
        return "Nie znalazłem miejsca „\(cleaned)”."
    }

    private static func endActiveRouteNow() -> String {
        guard let mapState = MapKitNavigationService.shared.mapState, mapState.isNavigating else {
            return "Nie ma aktywnej trasy do zakończenia."
        }
        DriveMateMemoryStore.shared.notifyTripEnded(
            destinationTitle: mapState.destinationTitle,
            destinationCoordinate: mapState.destinationCoordinate,
            subtitle: mapState.statusBanner ?? ""
        )
        let summary = mapState.endTripAndSummarize()
        NotificationCenter.default.post(
            name: .driveMateDidCancelRoute,
            object: nil,
            userInfo: [
                "duration": summary.durationSeconds,
                "distance": summary.distanceMeters,
                "avgSpeed": summary.averageSpeedKmh,
                "title": summary.destinationTitle as Any
            ]
        )
        return "Zakończyłem trasę."
    }

    private static func waitForLocation(timeoutMs: Int) async {
        if MapKitNavigationService.shared.location?.coordinate != nil { return }
        let steps = max(timeoutMs / 100, 1)
        for _ in 0..<steps {
            if MapKitNavigationService.shared.location?.coordinate != nil { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func startToCoordinate(_ saved: SavedPlace) async -> String {
        let place = MapKitNavigationService.PlaceResult(
            name: saved.label,
            address: saved.address,
            latitude: saved.latitude,
            longitude: saved.longitude,
            category: "saved"
        )
        return await startToPlaceResult(place)
    }

    private static func startToPlaceResult(_ place: MapKitNavigationService.PlaceResult) async -> String {
        guard NavigationEULA.isAccepted else {
            MapKitNavigationService.shared.setPendingDestination(place)
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return "Otwórz DriveMate i zaakceptuj warunki nawigacji, potem powtórz komendę."
        }
        guard MapKitNavigationService.shared.mapState != nil else {
            return "DriveMate nie jest jeszcze gotowy — spróbuj za chwilę."
        }
        await waitForLocation(timeoutMs: 5_000)
        guard MapKitNavigationService.shared.location?.coordinate != nil else {
            // Bez GPS MKDirections(.forCurrentLocation) pada — zapamiętaj cel i proś o otwarcie appki.
            MapKitNavigationService.shared.setPendingDestination(place)
            return "Mam cel \(place.name). Otwórz DriveMate, żebym złapał lokalizację i wystartował."
        }
        do {
            InterruptedRouteStore.shared.snapshotActiveNavigationIfNeeded()
            let result = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: place.latitude,
                toLongitude: place.longitude,
                destinationName: place.name
            )
            NotificationCenter.default.post(
                name: .driveMateDidNavigate,
                object: nil,
                userInfo: [
                    "title": place.name,
                    "subtitle": place.address,
                    "lat": place.latitude,
                    "lon": place.longitude
                ]
            )
            let minutes = Int((result.best.expectedSeconds / 60).rounded())
            return "Startuję do \(place.name), ok. \(minutes) min."
        } catch NavigationError.disclaimerRequired {
            MapKitNavigationService.shared.setPendingDestination(place)
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return "Zaakceptuj warunki nawigacji w DriveMate."
        } catch {
            MapKitNavigationService.shared.setPendingDestination(place)
            return "Nie udało się wyznaczyć trasy do \(place.name). Otwórz DriveMate i spróbuj ponownie."
        }
    }
}
