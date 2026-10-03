import Foundation
import MapKit
import Combine

struct PlaceSuggestion: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?

    static func == (lhs: PlaceSuggestion, rhs: PlaceSuggestion) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ResolvedPlace: Equatable {
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: ResolvedPlace, rhs: ResolvedPlace) -> Bool {
        lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Autouzupełnianie miejsc z Apple Maps (MKLocalSearchCompleter) + wyszukiwanie pełne.
@MainActor
final class PlaceAutocompleteService: NSObject, ObservableObject {
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    @Published private(set) var isSearching = false
    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            updateCompleter()
        }
    }

    private let completer = MKLocalSearchCompleter()
    private var region: MKCoordinateRegion?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func setUserRegion(coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 60_000,
            longitudinalMeters: 60_000
        )
        if let region { completer.region = region }
    }

    func clear() {
        query = ""
        suggestions = []
        isSearching = false
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> ResolvedPlace {
        if let completion = suggestion.completion {
            let request = MKLocalSearch.Request(completion: completion)
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                throw NavigationError.geocodeFailed
            }
            let coord = item.location.coordinate
            let title = item.name ?? suggestion.title
            let subtitle = [
                item.placemark.thoroughfare,
                item.placemark.locality
            ].compactMap { $0 }.joined(separator: ", ")
            return ResolvedPlace(
                title: title,
                subtitle: subtitle.isEmpty ? suggestion.subtitle : subtitle,
                coordinate: coord
            )
        }

        let places = try await MapKitNavigationService.shared.searchPlaces(
            query: suggestion.title,
            near: region?.center ?? MapKitNavigationService.shared.location?.coordinate,
            presentOnMap: false
        )
        guard let first = places.first else { throw NavigationError.geocodeFailed }
        return ResolvedPlace(
            title: first.name,
            subtitle: first.address,
            coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
        )
    }

    func resolveQuery(_ text: String) async throws -> ResolvedPlace {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NavigationError.geocodeFailed }
        let places = try await MapKitNavigationService.shared.searchPlaces(
            query: trimmed,
            near: region?.center ?? MapKitNavigationService.shared.location?.coordinate,
            presentOnMap: false
        )
        guard let first = places.first else { throw NavigationError.geocodeFailed }
        return ResolvedPlace(
            title: first.name,
            subtitle: first.address,
            coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
        )
    }

    private func updateCompleter() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else {
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = q
    }
}

extension PlaceAutocompleteService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.prefix(8).map { item in
            PlaceSuggestion(
                id: "\(item.title)|\(item.subtitle)",
                title: item.title,
                subtitle: item.subtitle,
                completion: item
            )
        }
        Task { @MainActor in
            self.suggestions = Array(results)
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
}
