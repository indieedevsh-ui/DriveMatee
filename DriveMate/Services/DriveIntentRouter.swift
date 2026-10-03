import Foundation
import CoreLocation

/// Lokalny router komend PL — działa nawet bez Foundation Models.
enum NavigateStartOrigin: Equatable {
    case myLocation
    case place(String)
}

enum DriveIntent: Equatable {
    /// Nawigacja. `start == nil` → zapytaj skąd; inaczej od razu trasa.
    case navigate(destination: String, start: NavigateStartOrigin?)
    case streetInfo(query: String?)
    case traffic(query: String?)
    case findFood
    /// Luźna odpowiedź (wiedza / rozmowa) — bez efektów mapy.
    case answer(replyHint: String)
    /// Funkcja spoza możliwości — uczciwa odmowa.
    case unsupported(replyHint: String)
    case unknown(raw: String)
}

enum DriveIntentParser {
    static func parse(_ text: String) -> DriveIntent {
        let cleaned = normalize(text)
        guard !cleaned.isEmpty else { return .unknown(raw: text) }
        let lower = cleaned.lowercased()

        // Jedzenie / głód
        if isFoodRequest(lower) {
            return .findFood
        }

        // Korki / ryzyko (przed nawigacją — „korki na …” nie ma być trasą)
        if isTraffic(lower) {
            let query = extractAfterKeywords(cleaned, keywords: [
                "korki na ulicy", "korek na ulicy", "korki na", "korek na",
                "ryzyko na", "utrudnienia na", "ruch na ulicy", "ruch na",
                "na ulicy", "ulicy", "dla", "na trasie"
            ])
            return .traffic(query: query)
        }

        // Info o ulicy
        if isStreetInfo(lower) {
            if lower.contains("obec") || lower.contains("tu ") || lower.contains("tutaj") {
                return .streetInfo(query: nil)
            }
            let query = extractAfterKeywords(cleaned, keywords: [
                "informacja o ulicy", "info o ulicy", "o ulicy", "ulicy",
                "na temat", "o "
            ])
            return .streetInfo(query: query ?? cleaned)
        }

        // Nawigacja z startem + celem w jednej wypowiedzi
        if let combo = extractNavigateWithStart(cleaned, lower: lower) {
            return combo
        }

        // Nawigacja / trasa (tylko cel)
        if isNavigation(lower) {
            if let dest = extractDestination(cleaned), dest.count > 1 {
                return .navigate(destination: dest, start: nil)
            }
            if let dest = stripNavigationPrefix(cleaned), dest.count > 1 {
                return .navigate(destination: dest, start: nil)
            }
        }

        // Krótka nazwa miejsca (np. „Rynek Dębnicki”) — ostrożnie
        if isBarePlaceName(cleaned, lower: lower) {
            return .navigate(destination: cleaned, start: nil)
        }

        return .unknown(raw: cleaned)
    }

    // MARK: - Classifiers

    private static func isFoodRequest(_ lower: String) -> Bool {
        let keys = [
            "głodn", "glodn", "jem", "zjem", "jeść", "jesc",
            "restaurac", "jedzenie", "coś do jedzenia", "cos do jedzenia",
            "fast food", "obiad", "kolacj", "śniadan", "sniadan",
            "pizza", "burger", "kebab", "kawa", "kawiarni",
            "gdzie zjeść", "gdzie zjesc", "najbliższa restaurac", "najblizsza restaurac",
            "hungry", "restaurant", "food", "eat"
        ]
        return keys.contains(where: { lower.contains($0) })
    }

    private static func isTraffic(_ lower: String) -> Bool {
        lower.contains("korek") || lower.contains("korki") || lower.contains("ryzyko")
            || lower.contains("utrudnien")
            || (lower.contains("ruch") && (lower.contains("ulic") || lower.contains("drog")))
    }

    private static func isStreetInfo(_ lower: String) -> Bool {
        lower.contains("histori") || lower.contains("informac") || lower.contains("opowiedz")
            || lower.contains("co to za ulic") || lower.contains("info o ulic")
            || (lower.contains("ulic") && (lower.contains("o ") || lower.contains("obec")))
    }

    private static func isNavigation(_ lower: String) -> Bool {
        let verbs = [
            "jedź", "jedz", "jedziemy", "jedźmy", "jedzmy",
            "zaprowadź", "zaprowadz", "zaprowadźcie",
            "zabierz", "weź mnie", "wez mnie", "weźcie",
            "prowadź", "prowadz", "pokieruj", "kieruj",
            "nawiguj", "nawigacja",
            "trasa", "trasę", "trase", "dojazd",
            "znajdź", "znajdz", "wyznacz",
            "dotrzeć", "dotrzec", "dojechać", "dojechac", "dojechać",
            "chciałbym dotrzeć", "chcialbym dotrzec", "chcę dotrzeć", "chce dotrzec",
            "leć", "lec", "lecimy",
            "go to", "take me", "navigate", "drive to", "drive me"
        ]
        if verbs.contains(where: { lower.contains($0) }) { return true }
        if lower.hasPrefix("do ") || lower.hasPrefix("na ") { return true }
        if lower.contains(" na rondo") || lower.contains(" do rondo") { return true }
        return false
    }

    private static func isBarePlaceName(_ cleaned: String, lower: String) -> Bool {
        let words = cleaned.split(separator: " ").map(String.init)
        guard words.count >= 1, words.count <= 6 else { return false }
        let blocked = ["cześć", "czesc", "hej", "hello", "dzięki", "dzieki", "ok", "dobra", "pomóż", "pomoc"]
        if blocked.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) { return false }
        let questionVerbs = ["jest", "mam", "gdzie", "ile", "jak", "czy", "co ", "kiedy", "dlaczego", "dlaczego", "wylosuj", "losuj"]
        if questionVerbs.contains(where: { lower.hasPrefix($0) }) { return false }
        if isNavigation(lower) || isTraffic(lower) || isStreetInfo(lower) || isFoodRequest(lower) { return false }

        let placeHints = [
            "rynek", "ulic", "park", "plac", "kościół", "kosciol", "dworzec", "centrum",
            "galeria", "most", "osiedle", "stadion", "lotnisko", "szpital", "muzeum",
            "wawel", "sukiennic", "młynówka", "mlynowka"
        ]
        if placeHints.contains(where: { lower.contains($0) }) { return true }
        // Multi-word proper-looking name (np. „Rynek Dębnicki”)
        return words.count >= 2
    }

    /// „z mojej lokalizacji do X” / „chcę dotrzeć do X z mojego punktu” / start custom.
    private static func extractNavigateWithStart(_ text: String, lower: String) -> DriveIntent? {
        let myStartMarkers = [
            "z swojej lokalizacji", "ze swojej lokalizacji", "z mojej lokalizacji",
            "z mojego punktu", "z mojej pozycji", "z mojej lokalizacja",
            "zaczynam z swojej lokalizacji", "zaczynam z mojej lokalizacji",
            "startuję z mojej lokalizacji", "startuje z mojej lokalizacji",
            "z lokalizacji", "z gps", "stąd", "stad", "from my location", "from here"
        ]
        let hasMyStart = myStartMarkers.contains(where: { lower.contains($0) })

        // Cel po „dotrzeć do” / „dojechać do” / „do ”
        let destPatterns = [
            "chcę dotrzeć do ", "chce dotrzec do ", "chciałbym dotrzeć do ", "chcialbym dotrzec do ",
            "chcę dojechać do ", "chce dojechac do ", "dotrzeć do ", "dotrzec do ",
            "dojechać do ", "dojechac do ", "dotrzeć na ", "dotrzec na ",
            "i chcę dotrzeć do ", "i chce dotrzec do ", "i dotrzeć do ",
            "jedź do ", "jedz do ", "jedź na ", "jedz na ",
            "do ", "na "
        ]

        if hasMyStart {
            if let dest = extractAfterFirstMatch(text, patterns: destPatterns), dest.count > 1 {
                let cleanedDest = stripTrailingStartClause(dest)
                if cleanedDest.count > 1 {
                    return .navigate(destination: cleanedDest, start: .myLocation)
                }
            }
        }

        // „do X z mojej lokalizacji” / „do X z mojego punktu”
        for marker in [
            " z mojej lokalizacji", " z swojej lokalizacji", " ze swojej lokalizacji",
            " z mojego punktu", " z mojej pozycji", " z lokalizacji", " stąd", " stad"
        ] {
            if let range = lower.range(of: marker) {
                let before = String(text[..<text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if let dest = extractDestination(before) ?? stripNavigationPrefix(before), dest.count > 1 {
                    return .navigate(destination: dest, start: .myLocation)
                }
                if isBarePlaceName(before, lower: before.lowercased()) {
                    return .navigate(destination: before, start: .myLocation)
                }
            }
        }

        // „z dworca do Wawelu” / „z ulicy X do Y”
        if lower.hasPrefix("z "), !hasMyStart {
            if let parsed = parseFromPlaceToDestination(text) {
                return parsed
            }
        }

        return nil
    }

    private static func parseFromPlaceToDestination(_ text: String) -> DriveIntent? {
        let lower = text.lowercased()
        guard let doRange = lower.range(of: " do ") ?? lower.range(of: " na ") else { return nil }
        let startPart = String(text[..<text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: doRange.lowerBound))])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let destPart = String(text[text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: doRange.upperBound))...])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        var start = startPart
        if start.lowercased().hasPrefix("z ") {
            start = String(start.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard start.count > 1, destPart.count > 1 else { return nil }
        if DriveIntentExecutor.isMyLocationPhrase(start) {
            return .navigate(destination: destPart, start: .myLocation)
        }
        return .navigate(destination: destPart, start: .place(start))
    }

    private static func extractAfterFirstMatch(_ text: String, patterns: [String]) -> String? {
        let lower = text.lowercased()
        for pattern in patterns.sorted(by: { $0.count > $1.count }) {
            if let range = lower.range(of: pattern) {
                let start = text.index(
                    text.startIndex,
                    offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound)
                )
                let value = String(text[start...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if value.count > 1 { return value }
            }
        }
        return nil
    }

    private static func stripTrailingStartClause(_ dest: String) -> String {
        var result = dest
        let lower = result.lowercased()
        for marker in [
            " z mojej lokalizacji", " z swojej lokalizacji", " ze swojej lokalizacji",
            " z mojego punktu", " z mojej pozycji", " z lokalizacji", " stąd", " stad"
        ] {
            if let range = lower.range(of: marker) {
                result = String(result[..<result.index(result.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))])
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: - Extraction

    private static func extractDestination(_ text: String) -> String? {
        // Dłuższe frazy najpierw
        let patterns = [
            "zaprowadź mnie proszę na ", "zaprowadź mnie proszę do ",
            "zaprowadz mnie prosze na ", "zaprowadz mnie prosze do ",
            "zaprowadź mnie na ", "zaprowadź mnie do ",
            "zaprowadz mnie na ", "zaprowadz mnie do ",
            "zaprowadź na ", "zaprowadź do ", "zaprowadz na ", "zaprowadz do ",
            "zabierz mnie na ", "zabierz mnie do ", "zabierz na ", "zabierz do ",
            "weź mnie na ", "weź mnie do ", "wez mnie na ", "wez mnie do ",
            "znajdź mi trasę do ", "znajdz mi trase do ",
            "znajdź trasę do ", "znajdz trase do ", "znajdź drogę do ", "znajdz droge do ",
            "wyznacz trasę do ", "wyznacz trase do ",
            "pokieruj mnie na ", "pokieruj mnie do ", "pokieruj na ", "pokieruj do ",
            "kieruj mnie na ", "kieruj mnie do ", "kieruj na ", "kieruj do ",
            "prowadź mnie na ", "prowadź mnie do ", "prowadź na ", "prowadź do ",
            "prowadz mnie na ", "prowadz mnie do ",
            "nawiguj mnie na ", "nawiguj mnie do ", "nawiguj na ", "nawiguj do ",
            "trasa do ", "trasę do ", "trase do ", "dojazd do ",
            "jedźmy na ", "jedźmy do ", "jedzmy na ", "jedzmy do ",
            "jedź proszę na ", "jedź proszę do ", "jedz prosze na ", "jedz prosze do ",
            "jedź na ", "jedź do ", "jedz na ", "jedz do ",
            "leć na ", "leć do ", "lec na ", "lec do ",
            "drive me to ", "take me to ", "navigate to ", "go to ",
            "do ", "na "
        ]
        let lower = text.lowercased()
        for pattern in patterns {
            if let range = lower.range(of: pattern) {
                let start = text.index(
                    text.startIndex,
                    offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound)
                )
                let dest = String(text[start...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if dest.count > 1 { return dest }
            }
        }
        return nil
    }

    /// Usuwa wiodące słowa nawigacyjne, gdy wzorzec słownikowy nie trafił.
    private static func stripNavigationPrefix(_ text: String) -> String? {
        var result = text
        let prefixes = [
            "zaprowadź mnie proszę", "zaprowadz mnie prosze",
            "zaprowadź mnie", "zaprowadz mnie", "zaprowadź", "zaprowadz",
            "zabierz mnie", "zabierz", "weź mnie", "wez mnie",
            "pokieruj mnie", "pokieruj", "kieruj mnie", "kieruj",
            "prowadź mnie", "prowadz mnie", "prowadź", "prowadz",
            "nawiguj mnie", "nawiguj",
            "znajdź mi trasę", "znajdz mi trase", "znajdź trasę", "znajdz trase",
            "wyznacz trasę", "wyznacz trase", "trasa", "trasę", "trase", "dojazd",
            "jedźmy", "jedzmy", "jedź proszę", "jedz prosze", "jedź", "jedz",
            "leć", "lec", "take me", "drive me", "navigate", "go"
        ]
        let lower = result.lowercased()
        for prefix in prefixes.sorted(by: { $0.count > $1.count }) {
            if lower.hasPrefix(prefix) {
                let idx = result.index(result.startIndex, offsetBy: prefix.count)
                result = String(result[idx...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                break
            }
        }
        // Odetnij łączniki do/na
        let lower2 = result.lowercased()
        for link in ["na ", "do ", "w stronę ", "w strone ", "kierunek "] {
            if lower2.hasPrefix(link) {
                let idx = result.index(result.startIndex, offsetBy: link.count)
                result = String(result[idx...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                break
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func extractAfterKeywords(_ text: String, keywords: [String]) -> String? {
        let lower = text.lowercased()
        for key in keywords.sorted(by: { $0.count > $1.count }) {
            if let range = lower.range(of: key) {
                let start = text.index(
                    text.startIndex,
                    offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound)
                )
                let value = String(text[start...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if value.count > 1 { return value }
            }
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wake = [
            "hey drive mate", "hej drive mate", "hey drivemate", "hej drivemate",
            "hey drive", "hej drive", "hei drive", "ej drive", "ok drive"
        ]
        let lower = s.lowercased()
        for phrase in wake.sorted(by: { $0.count > $1.count }) {
            if let range = lower.range(of: phrase) {
                let start = s.index(s.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
                let end = s.index(s.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                s.removeSubrange(start..<end)
                break
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

@MainActor
enum DriveIntentExecutor {
    static func execute(_ intent: DriveIntent) async -> String {
        switch intent {
        case .navigate(let destination, let start):
            return await executeNavigate(destination: destination, start: start)

        case .streetInfo(let query):
            do {
                if let query, !query.isEmpty {
                    let places = try await MapKitNavigationService.shared.searchPlaces(
                        query: query,
                        near: MapKitNavigationService.shared.location?.coordinate
                    )
                    if let first = places.first {
                        return "\(first.name). \(first.address.isEmpty ? first.category : first.address)."
                    }
                    return "Nie znalazłem informacji o „\(query)”."
                } else if let coordinate = MapKitNavigationService.shared.location?.coordinate {
                    let placemark = try await MapKitNavigationService.shared.reverseGeocode(coordinate: coordinate)
                    let name = [placemark.thoroughfare, placemark.subThoroughfare, placemark.locality]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    MapComplianceStore.shared.showPlace(
                        name: name.isEmpty ? "Twoja lokalizacja" : name,
                        coordinate: coordinate
                    )
                    return name.isEmpty ? "Nie udało się odczytać obecnej ulicy." : "Jesteś przy: \(name)."
                }
                return "Brak lokalizacji do odczytu obecnej ulicy."
            } catch {
                return "Nie udało się pobrać informacji o ulicy."
            }

        case .traffic(let query):
            do {
                var coordinate = MapKitNavigationService.shared.location?.coordinate
                if let query, !query.isEmpty {
                    let places = try await MapKitNavigationService.shared.searchPlaces(
                        query: query,
                        near: coordinate
                    )
                    if let first = places.first {
                        coordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
                    }
                }
                guard let coordinate else { return "Brak lokalizacji do oceny ruchu." }
                let snapshot = try await MapKitNavigationService.shared.trafficSnapshot(near: coordinate)
                let lines = snapshot.split(separator: "\n").prefix(3).joined(separator: ". ")
                return String(lines)
            } catch {
                return "Nie udało się ocenić korków."
            }

        case .findFood:
            guard let coordinate = MapKitNavigationService.shared.location?.coordinate else {
                return "Brak lokalizacji — nie mogę znaleźć restauracji."
            }
            let location = MapKitNavigationService.shared.location
            if let location, !location.allowsNearbyFoodOffer {
                return "Stoisz już dłużej niż 5 minut — nie proponuję restauracji. Jedź dalej albo poproś ponownie w trasie."
            }
            let interrupting = MapKitNavigationService.shared.mapState?.isNavigating == true
            return await RestaurantOfferService.shared.findAndPresentNearest(
                near: coordinate,
                interruptingActiveRoute: interrupting
            )

        case .answer(let hint):
            return hint

        case .unsupported(let hint):
            return hint.isEmpty
                ? "Tego jeszcze nie umiem zrobić w Drive Mate."
                : hint

        case .unknown:
            return ""
        }
    }

    private static func executeNavigate(destination: String, start: NavigateStartOrigin?) async -> String {
        do {
            guard let first = try await MapKitNavigationService.shared.findFirstPlace(
                query: destination,
                near: MapKitNavigationService.shared.location?.coordinate
            ) else {
                return "Nie znalazłem miejsca „\(destination)” — sprawdź nazwę albo podaj dokładniejszy adres."
            }

            NotificationCenter.default.post(
                name: .driveMateDidSelectDestination,
                object: nil,
                userInfo: [
                    "title": first.name,
                    "subtitle": first.address,
                    "lat": first.latitude,
                    "lon": first.longitude
                ]
            )

            switch start {
            case .myLocation:
                return await startRoute(
                    to: first,
                    fromLatitude: nil,
                    fromLongitude: nil,
                    startLabel: "Twojej lokalizacji"
                )

            case .place(let startQuery):
                guard let origin = try await MapKitNavigationService.shared.findFirstPlace(
                    query: startQuery,
                    near: MapKitNavigationService.shared.location?.coordinate
                ) else {
                    MapKitNavigationService.shared.setPendingDestination(first)
                    return "Cel: \(first.name). Nie znalazłem startu „\(startQuery)”. Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?"
                }
                return await startRoute(
                    to: first,
                    fromLatitude: origin.latitude,
                    fromLongitude: origin.longitude,
                    startLabel: origin.name
                )

            case nil:
                // Szablon: tylko cel → dopytaj o start
                MapKitNavigationService.shared.setPendingDestination(first)
                return "\(first.name). Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?"
            }
        } catch {
            return "Nie udało się znaleźć miejsca: \(error.localizedDescription)"
        }
    }

    private static func startRoute(
        to place: MapKitNavigationService.PlaceResult,
        fromLatitude: Double?,
        fromLongitude: Double?,
        startLabel: String
    ) async -> String {
        do {
            let result = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: place.latitude,
                toLongitude: place.longitude,
                destinationName: place.name,
                fromLatitude: fromLatitude,
                fromLongitude: fromLongitude
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
            return "Startuję z \(startLabel) do \(place.name), ok. \(minutes) min."
        } catch NavigationError.disclaimerRequired {
            MapKitNavigationService.shared.setPendingDestination(place)
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return "Zaakceptuj warunki nawigacji, potem potwierdź skąd startujemy."
        } catch {
            return "Nie udało się wyznaczyć trasy: \(error.localizedDescription)"
        }
    }

    /// Odpowiedź na „skąd start” po wybraniu samego celu.
    static func completePendingStart(fromReply text: String) async -> (reply: String, started: Bool) {
        guard let pending = MapKitNavigationService.shared.pendingDestination else {
            return ("", false)
        }

        if Self.isMyLocationPhrase(text) {
            do {
                let result = try await MapKitNavigationService.shared.planBestRoute(
                    toLatitude: pending.latitude,
                    toLongitude: pending.longitude,
                    destinationName: pending.name
                )
                NotificationCenter.default.post(
                    name: .driveMateDidNavigate,
                    object: nil,
                    userInfo: [
                        "title": pending.name,
                        "subtitle": pending.address,
                        "lat": pending.latitude,
                        "lon": pending.longitude
                    ]
                )
                let minutes = Int((result.best.expectedSeconds / 60).rounded())
                return ("Startuję z Twojej lokalizacji do \(pending.name), ok. \(minutes) min.", true)
            } catch NavigationError.disclaimerRequired {
                NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
                return ("Zaakceptuj warunki nawigacji, potem powiedz ponownie skąd jedziemy.", false)
            } catch {
                return ("Nie udało się wyznaczyć trasy: \(error.localizedDescription)", false)
            }
        }

        // Inny adres startowy
        let startQuery = Self.extractStartQuery(from: text)
        do {
            guard let start = try await MapKitNavigationService.shared.findFirstPlace(
                query: startQuery,
                near: MapKitNavigationService.shared.location?.coordinate
            ) else {
                return ("Nie znalazłem punktu startowego „\(startQuery)”. Powiedz „moja lokalizacja” albo inny adres.", false)
            }
            let result = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: pending.latitude,
                toLongitude: pending.longitude,
                destinationName: pending.name,
                fromLatitude: start.latitude,
                fromLongitude: start.longitude
            )
            NotificationCenter.default.post(
                name: .driveMateDidNavigate,
                object: nil,
                userInfo: [
                    "title": pending.name,
                    "subtitle": pending.address,
                    "lat": pending.latitude,
                    "lon": pending.longitude
                ]
            )
            let minutes = Int((result.best.expectedSeconds / 60).rounded())
            return ("Startuję z \(start.name) do \(pending.name), ok. \(minutes) min.", true)
        } catch NavigationError.disclaimerRequired {
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return ("Zaakceptuj warunki nawigacji, potem powiedz ponownie skąd jedziemy.", false)
        } catch {
            return ("Nie udało się wyznaczyć trasy: \(error.localizedDescription)", false)
        }
    }

    static func isMyLocationPhrase(_ text: String) -> Bool {
        let lower = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
        let phrases = [
            "moja lokalizacja", "mojej lokalizacji", "mojej lokalizacja",
            "swojej lokalizacji", "swoja lokalizacja", "ze swojej lokalizacji",
            "skorzystaj z mojej lokalizacji", "skorzystaj z lokalizacji",
            "uzyj mojej lokalizacji", "użyj mojej lokalizacji",
            "uzyj lokalizacji", "użyj lokalizacji",
            "z mojej lokalizacji", "z swojej lokalizacji", "z lokalizacji",
            "mojego punktu", "z mojego punktu", "moj punkt",
            "tu gdzie jestem", "tutaj gdzie jestem",
            "z tutaj", "stąd", "stad", "z stad", "z stąd",
            "obecna lokalizacja", "biezaca lokalizacja", "bieżąca lokalizacja",
            "gps", "moja pozycja", "z mojej pozycji",
            "my location", "current location", "use my location",
            "from here", "here"
        ]
        if phrases.contains(where: { lower.contains($0) }) { return true }
        let short = lower.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return [
            "tu", "tutaj", "stad", "stąd", "gps", "lokalizacja",
            "moja", "swoja", "z lokalizacji"
        ].contains(short)
    }

    private static func extractStartQuery(from text: String) -> String {
        var q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "zacznij z ", "start z ", "startuj z ", "zaczynam z ",
            "z adresu ", "z ulicy ", "z miejsca ",
            "adres startowy ", "punkt startowy ",
            "innego miejsca ", "z innego miejsca ",
            "z ", "od "
        ]
        let lower = q.lowercased()
        for p in prefixes {
            if lower.hasPrefix(p) {
                q = String(q.dropFirst(p.count))
                break
            }
        }
        return q.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
