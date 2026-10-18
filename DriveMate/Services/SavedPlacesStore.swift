import Foundation
import CoreLocation
import Combine
import AppIntents

/// Dom / praca / własne miejsca — trwałe do usunięcia w ustawieniach Drive Mate.
enum SavedPlaceSlot: String, Codable, Equatable, Hashable, CaseIterable {
    case home
    case work
    case custom

    var polishLabel: String {
        switch self {
        case .home: return "Dom"
        case .work: return "Praca"
        case .custom: return "Miejsce"
        }
    }

    var englishLabel: String {
        switch self {
        case .home: return "Home"
        case .work: return "Work"
        case .custom: return "Place"
        }
    }
}

struct SavedPlace: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var slot: SavedPlaceSlot
    /// Etykieta PL widoczna w UI (Dom / Praca / Siłownia…).
    var label: String
    /// Nazwa EN wyłącznie pod Siri / App Intents — nigdy nie pokazujemy w UI.
    var englishName: String
    var address: String
    /// Adres EN (cichy) — ułatwia Siri i geokodowanie.
    var englishAddress: String
    var latitude: Double
    var longitude: Double
    var updatedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var siriTitle: String {
        let name = englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? slot.englishLabel : name
    }
}

@MainActor
final class SavedPlacesStore: ObservableObject {
    static let shared = SavedPlacesStore()

    @Published private(set) var places: [SavedPlace] = []

    private let storageKey = "driveMate.savedPlaces.v1"

    private init() { load() }

    var home: SavedPlace? { places.first { $0.slot == .home } }
    var work: SavedPlace? { places.first { $0.slot == .work } }
    var customPlaces: [SavedPlace] { places.filter { $0.slot == .custom } }

    static func slot(forLabel label: String) -> SavedPlaceSlot {
        switch normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching(label)) {
        case "dom", "home", "house": return .home
        case "praca", "work", "office": return .work
        default: return .custom
        }
    }

    func place(id: UUID) -> SavedPlace? {
        places.first { $0.id == id }
    }

    /// Znane aliasy ról — dopasowanie TYLKO exact (bez contains — „szkola” ≠ „dom”).
    private static let roleAliasKeys: Set<String> = [
        "dom", "home", "house",
        "praca", "work", "office",
        "szkola", "school",
        "silownia", "gym", "fitness",
        "uczelnia", "uniwersytet", "akademia",
        "przedszkole", "biuro", "garaz"
    ]

    /// Dopasuj „dom”, „praca”, „szkoła” / „szkoły”, „home”, „UKEN” itd.
    func resolve(spokenQuery: String) -> SavedPlace? {
        var fold = DriveIntentQueryHelpers.foldForMatching(spokenQuery)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !fold.isEmpty else { return nil }

        // Zdejmij ogony nawigacji / zaimki PL+EN („to my school”, „jedz do szkoly”).
        for token in [
            "jedz do ", "jedz na ", "nawiguj mnie do ", "nawiguj do ",
            "poprowadz mnie do ", "prowadz mnie do ", "prowadz do ",
            "zaprowadz mnie do ", "zabierz mnie do ", "wez mnie do ",
            "navigate to ", "drive to ", "take me to ", "go to ",
            "to my ", "to the ", "to ", "my ", "the ",
            "do ", "na ", "w strone ", "moja ", "moj ", "moje ", "mojej ", "mojego "
        ] {
            if fold.hasPrefix(token) {
                fold = String(fold.dropFirst(token.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Ostatnie słowo często jest celem: „… do szkoly”
        if fold.contains(" "),
           let last = fold.split(separator: " ").last.map(String.init),
           Self.roleAliasKeys.contains(Self.normalizeAliasKey(last)) || last.count >= 3 {
            let lastKey = Self.normalizeAliasKey(last)
            if Self.roleAliasKeys.contains(lastKey) {
                fold = last
            }
        }

        let key = Self.normalizeAliasKey(fold)

        // 1) Role → slot / etykieta (strict)
        if key == "dom" { return home }
        if key == "praca" { return work }
        if Self.roleAliasKeys.contains(key) {
            if let role = places.first(where: {
                Self.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching($0.label)) == key
                    || Self.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching($0.englishName)) == key
            }) {
                return role
            }
            // Znany alias, ale niezapisany — nie zgaduj domu po contains.
            return nil
        }

        // 2) Exact etykieta / EN
        if let exact = places.first(where: {
            DriveIntentQueryHelpers.foldForMatching($0.label) == fold
                || DriveIntentQueryHelpers.foldForMatching($0.englishName) == fold
                || Self.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching($0.label)) == key
                || Self.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching($0.englishName)) == key
        }) {
            return exact
        }

        // 3) Nazwa POI w adresie (UKEN) — tylko dłuższe frazy, bez contains krótkich aliasów.
        guard fold.count >= 3 else { return nil }
        return places.first(where: { place in
            let addr = DriveIntentQueryHelpers.foldForMatching(place.address)
            let enAddr = DriveIntentQueryHelpers.foldForMatching(place.englishAddress)
            let titleBits = [addr, enAddr].filter { $0.count >= 3 }
            return titleBits.contains { hay in
                hay == fold
                    || hay.hasPrefix(fold + ",")
                    || hay.hasPrefix(fold + " ")
                    || hay.contains(" " + fold + ",")
                    || hay.contains(" " + fold + " ")
                    || hay.hasSuffix(" " + fold)
                    || hay.contains(fold + ",")
            }
        })
    }

    /// Czy wypowiedź to znany alias roli (szkoła/dom/…), nawet jeśli jeszcze nie zapisany.
    static func isKnownRoleAlias(_ spokenQuery: String) -> Bool {
        var fold = DriveIntentQueryHelpers.foldForMatching(spokenQuery)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let last = fold.split(separator: " ").last.map(String.init) {
            fold = last
        }
        return roleAliasKeys.contains(normalizeAliasKey(fold))
    }

    /// „szkoły” / „szkole” → „Szkoła”; „silownie” → „Siłownia”.
    static func canonicalLabel(for raw: String) -> String {
        let fold = normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching(raw))
        switch fold {
        case "dom", "home", "house": return "Dom"
        case "praca", "work", "office": return "Praca"
        case "szkola", "school": return "Szkoła"
        case "uniwersytet": return "Uniwersytet"
        case "uczelnia": return "Uczelnia"
        case "akademia": return "Akademia"
        case "silownia", "gym", "fitness": return "Siłownia"
        case "przedszkole": return "Przedszkole"
        case "biuro": return "Biuro"
        case "garaz": return "Garaż"
        default:
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first else { return trimmed }
            return String(first).uppercased() + trimmed.dropFirst()
        }
    }

    /// Ujednolicenie odmian pod matching (szkoly → szkola).
    static func normalizeAliasKey(_ fold: String) -> String {
        let t = fold.trimmingCharacters(in: .whitespacesAndNewlines)
        switch t {
        case "szkoly", "szkole", "szkola", "school": return "szkola"
        case "silownie", "silowni", "silownia", "gym", "fitness": return "silownia"
        case "uczelni", "uczelnie", "uczelnia": return "uczelnia"
        case "uniwersytetu", "uniwersytecie", "uniwersytet": return "uniwersytet"
        case "akademii", "akademie", "akademia": return "akademia"
        case "przedszkola", "przedszkolu", "przedszkole": return "przedszkole"
        case "biura", "biurze", "biuro": return "biuro"
        case "garazu", "garaz": return "garaz"
        case "domu", "domem", "dom": return "dom"
        case "pracy", "prace", "praca": return "praca"
        default: return t
        }
    }

    @discardableResult
    func upsert(
        slot: SavedPlaceSlot,
        label: String,
        englishName: String,
        address: String,
        englishAddress: String,
        coordinate: CLLocationCoordinate2D
    ) -> SavedPlace {
        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = cleanedLabel.isEmpty ? slot.polishLabel : cleanedLabel
        let enName = englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEN = enName.isEmpty ? slot.englishLabel : enName

        if slot == .home || slot == .work {
            if let idx = places.firstIndex(where: { $0.slot == slot }) {
                places[idx].label = finalLabel
                places[idx].englishName = finalEN
                places[idx].address = address
                places[idx].englishAddress = englishAddress
                places[idx].latitude = coordinate.latitude
                places[idx].longitude = coordinate.longitude
                places[idx].updatedAt = .now
                persist()
                notifyShortcutsChanged()
                return places[idx]
            }
        } else if let idx = places.firstIndex(where: {
            $0.slot == .custom && DriveIntentQueryHelpers.foldForMatching($0.label) == DriveIntentQueryHelpers.foldForMatching(finalLabel)
        }) {
            places[idx].englishName = finalEN
            places[idx].address = address
            places[idx].englishAddress = englishAddress
            places[idx].latitude = coordinate.latitude
            places[idx].longitude = coordinate.longitude
            places[idx].updatedAt = .now
            persist()
            notifyShortcutsChanged()
            return places[idx]
        }

        let place = SavedPlace(
            id: UUID(),
            slot: slot,
            label: finalLabel,
            englishName: finalEN,
            address: address,
            englishAddress: englishAddress,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            updatedAt: .now
        )
        places.insert(place, at: 0)
        persist()
        notifyShortcutsChanged()
        return place
    }

    func remove(id: UUID) {
        places.removeAll { $0.id == id }
        persist()
        notifyShortcutsChanged()
    }

    func clearAll() {
        places.removeAll()
        persist()
        notifyShortcutsChanged()
    }

    private func notifyShortcutsChanged() {
        DriveMateAppShortcuts.updateAppShortcutParameters()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) else {
            places = []
            return
        }
        places = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
