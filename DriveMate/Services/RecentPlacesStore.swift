import Foundation
import CoreLocation
import Combine

struct RecentPlace: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var usedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var shortLabel: String {
        if title.count <= 22 { return title }
        return String(title.prefix(20)) + "…"
    }
}

@MainActor
final class RecentPlacesStore: ObservableObject {
    @Published private(set) var places: [RecentPlace] = []

    private let maxCount = 8
    private let key = "recentPlaces.v1"

    init() { load() }

    var topFour: [RecentPlace] {
        Array(places.prefix(4))
    }

    func add(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        places.removeAll {
            $0.title.caseInsensitiveCompare(cleanedTitle) == .orderedSame
                || (abs($0.latitude - coordinate.latitude) < 0.00015
                    && abs($0.longitude - coordinate.longitude) < 0.00015)
        }
        let item = RecentPlace(
            id: UUID(),
            title: cleanedTitle,
            subtitle: subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            usedAt: .now
        )
        places.insert(item, at: 0)
        if places.count > maxCount {
            places = Array(places.prefix(maxCount))
        }
        persist()
    }

    func clear() {
        places.removeAll()
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentPlace].self, from: data) else {
            places = []
            return
        }
        places = decoded.sorted { $0.usedAt > $1.usedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
