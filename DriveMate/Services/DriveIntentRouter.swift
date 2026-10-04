import Foundation
import CoreLocation
import MapKit
import UIKit

/// Lokalny router komend PL — działa nawet bez Foundation Models.
enum NavigateStartOrigin: Equatable {
    case myLocation
    case place(String)
}

enum MusicPlaybackCommand: Equatable {
    case pause
    case resume
    case toggle
    case next
    case previous
}

enum DriveIntent: Equatable {
    /// Nawigacja. `start == nil` → zapytaj skąd; inaczej od razu trasa.
    case navigate(destination: String, start: NavigateStartOrigin?)
    case streetInfo(query: String?)
    case streetHistory(query: String?)
    case traffic(query: String?)
    case findFood
    case cancelListening
    case cancelRoute
    /// Przywróć trasę przerwaną przez zjazd (restauracja / stacja / nowa nawigacja).
    case restoreInterruptedRoute
    case music(MusicPlaybackCommand)
    case speedLimit
    case fuelCost
    /// Najbliższa stacja; `preferCheapest` = szukaj pod kątem ceny (bez live cen MapKit — ranking dystansu + informacja).
    case nearestFuel(preferCheapest: Bool)
    /// Zapis modelu auta (np. „Toyota Corolla”).
    case setCarModel(String)
    /// Nawigacja do miejsca odwiedzonego N dni temu (0 = dziś).
    case navigateToPastVisit(daysAgo: Int)
    /// Ukryj / pokaż kafelek UI nawigacji.
    case setChromeTile(tileQuery: String, visible: Bool)
    /// Luźna odpowiedź (wiedza / rozmowa) — bez efektów mapy.
    case answer(replyHint: String)
    /// Funkcja spoza możliwości — uczciwa odmowa.
    case unsupported(replyHint: String)
    case unknown(raw: String)
}

enum DriveIntentParser {
    /// Dopasowanie bez polskich znaków — ASR często gubi diakrytyki.
    private static func folded(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
    }

    static func parse(_ text: String) -> DriveIntent {
        let cleaned = normalize(text)
        guard !cleaned.isEmpty else { return .unknown(raw: text) }
        let lower = folded(cleaned)

        // Anuluj nasłuch / trasę / przywróć przerwaną (przed chrome — „przywróć”)
        if isCancelListening(lower) { return .cancelListening }
        // Muzyka PRZED przywracaniem trasy — „poprzedni utwór” ≠ restore
        if let music = extractMusicCommand(from: lower) {
            return .music(music)
        }
        if isRestoreInterruptedRoute(lower) { return .restoreInterruptedRoute }
        if isCancelRoute(lower) { return .cancelRoute }

        // Model auta
        if let model = extractCarModel(from: cleaned, lower: lower) {
            return .setCarModel(model)
        }

        // „Tam gdzie byłem 2 dni temu”
        if let days = extractPastVisitDays(from: lower) {
            return .navigateToPastVisit(daysAgo: days)
        }

        // Ukryj / pokaż kafelki UI
        if let chrome = extractChromeVisibility(from: lower) {
            return .setChromeTile(tileQuery: chrome.query, visible: chrome.visible)
        }

        // Prędkość / paliwo / stacje
        if isSpeedLimit(lower) { return .speedLimit }
        if isFuelCost(lower) { return .fuelCost }
        if isNearestFuel(lower) {
            return .nearestFuel(preferCheapest: isCheapestFuel(lower))
        }

        // Jedzenie / głód
        if isFoodRequest(lower) {
            return .findFood
        }

        // Historia ulicy (przed ogólnym streetInfo)
        if isStreetHistory(lower) {
            if lower.contains("obec") || lower.contains("tu ") || lower.contains("tutaj") || lower.contains("tej ulic") {
                return .streetHistory(query: nil)
            }
            let query = extractAfterKeywords(cleaned, keywords: [
                "historia ulicy", "historię ulicy", "historie ulicy",
                "historia ", "o historii ", "opowiedz o ", "opowiedz historię "
            ])
            return .streetHistory(query: query)
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
            "glodn", "glodny", "glodna", "glodni", "zaglodn",
            "jem", "zjem", "zjesc", "jesc", "posilek", "posilku",
            "restaurac", "restauracja", "restauracje", "restauracji", "restauracie",
            "jedzenie", "cos do jedzenia", "cos zjesc", "chce zjesc", "chcialbym zjesc",
            "ochote na", "ochota na", "na zab",
            "fast food", "obiad", "obiadu", "kolacj", "sniadan", "lunch", "brunch",
            "pizza", "burger", "kebab", "sushi", "ramen", "mcdonald", "mc donald",
            "kawa", "kawiarni", "kawiarnie", "bar mlecz", "stolowk",
            "gdzie zjesc", "gdzie cos zjesc", "najblizsza restaurac", "najblizszy lokal",
            "najblizszy bar", "najblizsza knajp", "knajp", "lokal gastronom",
            "znajdz restaurac", "szukam restaurac", "pokaz restaurac",
            "hungry", "restaurant", "food", "eat", "nearest restaurant", "grab food"
        ]
        return keys.contains(where: { lower.contains($0) })
    }

    private static func isCancelListening(_ lower: String) -> Bool {
        let keys = [
            "anuluj nasluch", "wylacz nasluch",
            "przestan sluchac", "stop listening",
            "nie sluchaj", "zamknij asystenta"
        ]
        return keys.contains { lower.contains($0) }
    }

    private static func isCancelRoute(_ lower: String) -> Bool {
        let keys = [
            "anuluj trase", "anuluj nawigacj", "zakoncz trase",
            "zakoncz nawigacj", "wylacz nawigacj",
            "stop navigation", "cancel route", "cancel navigation",
            "przestan nawigowac", "nie chce jechac"
        ]
        return keys.contains { lower.contains($0) }
    }

    private static func isRestoreInterruptedRoute(_ lower: String) -> Bool {
        // Wymagaj kontekstu trasy — samotne „poprzedni” / „wznów” to nie restore.
        let hasRouteWord = lower.contains("tras") || lower.contains("nawigacj") || lower.contains("route")
            || lower.contains("przerwan") || lower.contains("tam gdzie jecha")
        guard hasRouteWord else { return false }

        let restoreKeys = [
            "przywróć", "przywroc",
            "wróć do", "wroc do", "wróć na", "wroc na",
            "wznów", "wznow",
            "wcześniejsz", "wczesniejsz", "poprzedni", "przerwan",
            "restore route", "previous route", "resume route"
        ]
        guard restoreKeys.contains(where: { lower.contains($0) }) else { return false }
        // „przywróć prędkościomierz” / muzyka ≠ trasa
        if lower.contains("kafelek") || lower.contains("prędkościomierz") || lower.contains("predkosciomierz")
            || lower.contains("zegar") || lower.contains("panel")
            || lower.contains("utwór") || lower.contains("utwor") || lower.contains("piosenk")
            || lower.contains("muzyk") || lower.contains("track") || lower.contains("odtwarzacz") {
            return false
        }
        return true
    }

    private static func extractMusicCommand(from lower: String) -> MusicPlaybackCommand? {
        let musicContext = lower.contains("muzyk") || lower.contains("utwór") || lower.contains("utwor")
            || lower.contains("piosenk") || lower.contains("track") || lower.contains("playlist")
            || lower.contains("odtwarzacz") || lower.contains("song") || lower.contains("audio")

        let navConflict = lower.contains("zjazd") || lower.contains("skrzyż") || lower.contains("skrzyz")
            || lower.contains("ulic") || lower.contains("tras") || lower.contains("nawig")
            || lower.contains("kilometr") || lower.contains(" metr")

        // Następny / poprzedni
        let wantsPrevious = lower.contains("poprzedni") || lower.contains("wcześniejsz") || lower.contains("wczesniejsz")
            || lower.contains("cofnij") || lower.contains("previous") || lower.contains("last track")
            || lower.contains("cofnij utwor") || lower.contains("cofnij utwór")
        let wantsNext = lower.contains("następn") || lower.contains("kolejn") || lower.contains("skip")
            || lower.contains("next") || lower == "dalej" || lower.hasPrefix("dalej ")
            || lower.contains("przesuń") || lower.contains("przesun")

        if wantsPrevious {
            if musicContext { return .previous }
            // Krótkie komendy do panelu odtwarzacza (bez konfliktu z nawigacją)
            if !navConflict, lower == "poprzedni" || lower.hasPrefix("poprzedni ")
                || lower == "cofnij" || lower.hasPrefix("cofnij ") {
                return .previous
            }
        }
        if wantsNext {
            if musicContext || lower.contains("skip") { return .next }
            if !navConflict, lower == "następny" || lower == "nastepny" || lower == "kolejny"
                || lower.hasPrefix("następn") || lower.hasPrefix("nastepn") || lower.hasPrefix("kolejn") {
                return .next
            }
        }

        if lower.contains("odpauzuj") || lower.contains("od pauz")
            || lower.contains("wznów muzyk") || lower.contains("wznow muzyk")
            || lower.contains("wznów piosen") || lower.contains("wznow piosen")
            || lower.contains("puść muzyk") || lower.contains("pusc muzyk")
            || lower.contains("puść piosen") || lower.contains("pusc piosen")
            || lower.contains("włącz muzyk") || lower.contains("wlacz muzyk")
            || lower.contains("włącz odtwarz") || lower.contains("wlacz odtwarz")
            || lower.contains("graj muzyk") || lower.contains("play music")
            || lower.contains("odtwórz") || lower.contains("odtworz")
            || lower == "play" || lower == "graj" || lower == "puść" || lower == "pusc"
            || (musicContext && (lower.contains("wznów") || lower.contains("wznow") || lower.contains("graj") || lower.contains("play") || lower.contains("puść") || lower.contains("pusc") || lower.contains("włącz") || lower.contains("wlacz"))) {
            return .resume
        }

        if lower.contains("pauza") || lower.contains("pause")
            || lower.contains("zatrzymaj muzyk") || lower.contains("zatrzymaj piosen")
            || lower.contains("zatrzymaj odtwarz") || lower.contains("wstrzymaj muzyk")
            || lower.contains("wycisz muzyk") || lower.contains("stop music")
            || lower == "stop" || lower == "pause"
            || (musicContext && (lower.contains("zatrzymaj") || lower.contains("zatrzym") || lower.contains("stop") || lower.contains("wstrzymaj"))) {
            return .pause
        }

        if lower == "pauza" || lower == "pause" { return .pause }
        if lower == "odpauzuj" || lower == "play" { return .resume }
        if (lower.contains("toggle") || lower.contains("przełącz") || lower.contains("przelacz")) && musicContext {
            return .toggle
        }

        return nil
    }

    private static func isSpeedLimit(_ lower: String) -> Bool {
        let keys = [
            "maksymalna predkosc", "limit predkosci",
            "ile moge jechac", "jaka predkosc",
            "predkosc maksymalna", "dozwolona predkosc",
            "speed limit", "ile max", "max predkosc"
        ]
        return keys.contains { lower.contains($0) }
    }

    private static func isFuelCost(_ lower: String) -> Bool {
        // Nie mylić z „stacja paliw” / tankowaniem — to nearestFuel.
        if isNearestFuel(lower), !lower.contains("koszt"), !lower.contains("spal"),
           !lower.contains("zuzyc"), !lower.contains("litr"), !lower.contains("ile zl"),
           !lower.contains("ile bedzie") {
            return false
        }
        let keys = [
            "ile paliwa", "ile paliva", "ile spal", "ile spale", "ile spalimy", "ile zuzyje",
            "koszt paliwa", "koszt paliva", "koszt przejazdu", "koszt trasy", "cena przejazdu",
            "ile bedzie kosztowac", "ile bedzie koszt", "ile to bedzie kosztowac",
            "ile bedzie kosztowalo", "ile zaplace", "ile zaplace za paliwo", "ile zl paliwo",
            "zuzycie paliwa", "zuzycie paliva", "zuzycie na trasie", "zusycie paliwa",
            "ile litrow", "ile litrow zuzyje", "spalanie", "spalanie na trasie", "spalanie paliwa",
            "fuel cost", "fuel consumption", "how much fuel", "gas cost"
        ]
        if keys.contains(where: { lower.contains($0) }) { return true }
        // Luźniejsze: „paliwo” + pytanie o ilość/koszt
        let asksQuantity = lower.contains("ile") || lower.contains("koszt") || lower.contains("cena")
            || lower.contains("spal") || lower.contains("zuzyc") || lower.contains("litr")
        let aboutFuel = lower.contains("paliw") || lower.contains("paliv") || lower.contains("benzyn")
            || lower.contains("spalan") || lower.contains("fuel")
        return asksQuantity && aboutFuel
    }

    private static func isNearestFuel(_ lower: String) -> Bool {
        let keys = [
            "stacja paliw", "stacje paliw", "stacji paliw", "stacje benzyn",
            "najblizsza stacja", "najblizsza stacje", "gdzie stacja", "gdzie zatankowac",
            "benzyna", "orlen", "shell", "bp ", "stacja benzyn",
            "gas station", "petrol", "tankowac", "zatankowac", "tankowanie",
            "najblizszy orlen", "stacja paliwo"
        ]
        return keys.contains { lower.contains($0) }
    }

    private static func isCheapestFuel(_ lower: String) -> Bool {
        lower.contains("najtani") || lower.contains("najlepsz") || lower.contains("tanio")
            || lower.contains("cena") || lower.contains("cene")
            || lower.contains("cheapest") || lower.contains("best price")
    }

    private static func isStreetHistory(_ lower: String) -> Bool {
        (lower.contains("histori") && (lower.contains("ulic") || lower.contains("miejsc") || lower.contains("tej")))
            || lower.contains("opowiedz o ulic") || lower.contains("ciekawostk")
    }

    private static func extractCarModel(from text: String, lower: String) -> String? {
        let prefixes = [
            "moj samochod to ", "moje auto to ",
            "jezdze ",
            "mam auto ", "mam samochod ",
            "model auta ", "samochod ", "auto to ",
            "my car is ", "i drive "
        ]
        for p in prefixes {
            if let range = lower.range(of: p) {
                let start = text.index(
                    text.startIndex,
                    offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound)
                )
                let model = String(text[start...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if model.count >= 2 { return model }
            }
        }
        return nil
    }

    private static func extractPastVisitDays(from lower: String) -> Int? {
        let triggers = [
            "gdzie pojechałem", "gdzie pojechalem", "gdzie byłem", "gdzie bylem",
            "tam gdzie jechałem", "tam gdzie jechalem", "ostatnio odwiedzon",
            "miejsce z ", "pokieruj tam gdzie", "weź mnie tam gdzie", "wez mnie tam gdzie",
            "jedź tam gdzie", "jedz tam gdzie", "tam gdzie byłem", "tam gdzie bylem"
        ]
        guard triggers.contains(where: { lower.contains($0) }) else {
            // „przedwczoraj” bez innych słów też
            if lower.contains("przedwczoraj") { return 2 }
            return nil
        }
        if lower.contains("przedwczoraj") { return 2 }
        if lower.contains("wczoraj") { return 1 }
        if lower.contains("dziś") || lower.contains("dzis") || lower.contains("today") { return 0 }

        // „2 dni temu” / „dwa dni temu”
        let wordNums: [(String, Int)] = [
            ("trzy dni", 3), ("3 dni", 3),
            ("dwa dni", 2), ("2 dni", 2),
            ("jeden dzień", 1), ("1 dzień", 1), ("1 dzien", 1)
        ]
        for (phrase, days) in wordNums {
            if lower.contains(phrase) { return min(days, 3) }
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*dn"#, options: []),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(match.range(at: 1), in: lower),
           let n = Int(lower[r]) {
            return min(max(n, 0), 3)
        }
        // „tam gdzie pojechałem” bez liczby → wczoraj jako domyślne
        return 1
    }

    private static func extractChromeVisibility(from lower: String) -> (query: String, visible: Bool)? {
        let hideKeys = [
            "ukryj", "schowaj", "wyłącz", "wylacz", "hide", "ukryć", "ukryc",
            "nie pokazuj", "zdejmij"
        ]
        let showKeys = [
            "pokaż", "pokaz", "pokaż mi", "pokaz mi", "włącz", "wlacz",
            "przywróć", "przywroc", "odkryj", "show", "wyświetl", "wyswietl"
        ]

        let isHide = hideKeys.contains { lower.contains($0) }
        let isShow = showKeys.contains { lower.contains($0) }
        guard isHide || isShow else { return nil }

        // Przywracanie trasy — nie chrome
        if isRestoreInterruptedRoute(lower) { return nil }

        // Nie ruszamy chronionych elementów
        if lower.contains("zakoncz") || lower.contains("zakończ") || lower.contains("koniec trasy")
            || lower.contains("muzyk") || lower.contains("skręt") || lower.contains("skret")
            || lower.contains("nawigacj") && (lower.contains("kafelek skret") || lower.contains("kafelek skręt")) {
            return nil
        }

        // Po słowie kluczowym weź resztę jako query kafelka
        var query = lower
        for key in (hideKeys + showKeys).sorted(by: { $0.count > $1.count }) {
            if let r = query.range(of: key) {
                query = String(query[r.upperBound...])
                break
            }
        }
        query = query
            .replacingOccurrences(of: "mi ", with: " ")
            .replacingOccurrences(of: "kafelek ", with: " ")
            .replacingOccurrences(of: "kafelki ", with: " ")
            .replacingOccurrences(of: "panel ", with: " ")
            .replacingOccurrences(of: "przycisk ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        // Domyślne skróty bez „kafelek”
        if query.isEmpty {
            if lower.contains("predkosciomierz") || lower.contains("prędkościomierz") || lower.contains("predkosc") {
                query = "prędkościomierz"
            } else if lower.contains("zegar") || lower.contains("godzin") {
                query = "zegar"
            } else if lower.contains("drive") {
                query = "drive"
            }
        }

        guard !query.isEmpty else { return nil }
        // Preferuj hide gdy oba (np. „nie pokazuj”)
        let visible = isHide ? false : true
        return (query, visible)
    }

    private static func isTraffic(_ lower: String) -> Bool {
        lower.contains("korek") || lower.contains("korki") || lower.contains("ryzyko")
            || lower.contains("utrudnien")
            || (lower.contains("ruch") && (lower.contains("ulic") || lower.contains("drog")))
    }

    private static func isStreetInfo(_ lower: String) -> Bool {
        lower.contains("histori") || lower.contains("informac") || lower.contains("opowiedz")
            || lower.contains("co to za ulic") || lower.contains("info o ulic")
            || lower.contains("powiedz o ulic") || lower.contains("co wiesz o ulic")
            || lower.contains("dane o ulic") || lower.contains("teryt")
            || (lower.contains("ulic") && (lower.contains("o ") || lower.contains("obec") || lower.contains("tej")))
    }

    private static func isNavigation(_ lower: String) -> Bool {
        let verbs = [
            "jedz", "jedziemy", "jedzmy",
            "zaprowadz", "zabierz", "wez mnie", "wezcie",
            "prowadz", "pokieruj", "kieruj",
            "nawiguj", "nawigacja", "nawigacje", "nawigowaniu",
            "trasa", "trase", "dojazd", "dojazdu",
            "znajdz", "wyznacz",
            "dotrzec", "dojechac",
            "chcialbym dotrzec", "chce dotrzec", "chce dojechac",
            "lec", "lecimy",
            "konfiguruj trase", "ustaw trase", "ustaw nawigacje",
            "prowadz mnie", "zaprowadź mnie", "zaprowadz mnie",
            "go to", "take me", "navigate", "drive to", "drive me",
            "directions to", "route to"
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
            "wawel", "sukiennic", "mlynowka"
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
            "startuje z mojej lokalizacji", "startuje z lokalizacji",
            "z lokalizacji", "z gps", "stad", "from my location", "from here",
            "z mojej pozycji gps", "tu gdzie jestem"
        ]
        let hasMyStart = myStartMarkers.contains(where: { lower.contains($0) })

        // Cel po „dotrzeć do” / „dojechać do” / „do ” — wzorce bez diakrytyków (lower jest folded).
        let destPatterns = [
            "chce dotrzec do ", "chcialbym dotrzec do ",
            "chce dojechac do ", "dotrzec do ",
            "dojechac do ", "dotrzec na ",
            "i chce dotrzec do ", "i dotrzec do ",
            "jedz do ", "jedz na ",
            "do ", "na "
        ]

        if hasMyStart {
            if let dest = extractAfterFirstMatchFolded(text, lower: lower, patterns: destPatterns), dest.count > 1 {
                let cleanedDest = stripTrailingStartClause(dest)
                if cleanedDest.count > 1 {
                    return .navigate(destination: cleanedDest, start: .myLocation)
                }
            }
        }

        // „do X z mojej lokalizacji” / „do X z mojego punktu”
        for marker in [
            " z mojej lokalizacji", " z swojej lokalizacji", " ze swojej lokalizacji",
            " z mojego punktu", " z mojej pozycji", " z lokalizacji", " stad"
        ] {
            if let range = lower.range(of: marker) {
                let before = String(text[..<text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if let dest = extractDestination(before) ?? stripNavigationPrefix(before), dest.count > 1 {
                    return .navigate(destination: dest, start: .myLocation)
                }
                if isBarePlaceName(before, lower: folded(before)) {
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
        extractAfterFirstMatchFolded(text, lower: folded(text), patterns: patterns)
    }

    /// Szuka wzorca w `lower` (już folded) i wycina odpowiadający fragment z oryginalnego `text`.
    private static func extractAfterFirstMatchFolded(_ text: String, lower: String, patterns: [String]) -> String? {
        for pattern in patterns.sorted(by: { $0.count > $1.count }) {
            let needle = folded(pattern)
            if let range = lower.range(of: needle) {
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
        let lower = folded(result)
        for marker in [
            " z mojej lokalizacji", " z swojej lokalizacji", " ze swojej lokalizacji",
            " z mojego punktu", " z mojej pozycji", " z lokalizacji", " stad"
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
            return await executeStreetInfoCard(query: query, historical: false)

        case .setCarModel(let model):
            return executeSetCarModel(model)

        case .navigateToPastVisit(let daysAgo):
            return await executePastVisit(daysAgo: daysAgo)

        case .setChromeTile(let query, let visible):
            return executeChromeVisibility(query: query, visible: visible)

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
            // Jawna prośba głosowa zawsze dozwolona (także „najbliższa restauracja” na postoju).
            let interrupting = MapKitNavigationService.shared.mapState?.isNavigating == true
            return await RestaurantOfferService.shared.findAndPresentNearest(
                near: coordinate,
                interruptingActiveRoute: interrupting
            )

        case .cancelListening:
            return "OK, wyłączam."

        case .cancelRoute:
            guard let mapState = MapKitNavigationService.shared.mapState, mapState.isNavigating else {
                return "Nie ma aktywnej trasy do anulowania."
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
            return "Anulowałem trasę."

        case .restoreInterruptedRoute:
            return await executeRestoreInterruptedRoute()

        case .music(let command):
            return executeMusic(command)

        case .speedLimit:
            return await executeSpeedLimit()

        case .streetHistory(let query):
            return await executeStreetInfoCard(query: query, historical: true)

        case .fuelCost:
            return executeFuelCost()

        case .nearestFuel(let preferCheapest):
            return await executeNearestFuel(preferCheapest: preferCheapest)

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

    private static func executeSpeedLimit() async -> String {
        guard let coordinate = MapKitNavigationService.shared.location?.coordinate else {
            return "Brak lokalizacji — nie mogę ocenić limitu prędkości."
        }
        do {
            let placemark = try await MapKitNavigationService.shared.reverseGeocode(coordinate: coordinate)
            let street = [placemark.thoroughfare, placemark.subThoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            let city = placemark.locality ?? ""
            let notices = MapKitNavigationService.shared.mapState?.route?.advisoryNotices ?? []
            var parts: [String] = []
            if !street.isEmpty {
                parts.append("Jesteś na \(street)\(city.isEmpty ? "" : ", \(city)").")
            }
            let typical = 50
            parts.append(
                "Apple Maps nie podaje tu dokładnego limitu ze znaku. W terenie zabudowanym zwykle obowiązuje \(typical) km/h — zawsze sprawdzaj znaki."
            )
            if let notice = notices.first, !notice.isEmpty {
                parts.append("Uwaga z trasy: \(notice).")
            }
            return parts.joined(separator: " ")
        } catch {
            return "Nie udało się odczytać odcinka. Patrz na znaki — w terenie zabudowanym zwykle 50 km/h."
        }
    }

    private static func executeStreetInfoCard(query: String?, historical: Bool) async -> String {
        do {
            var title = ""
            var coordinate = MapKitNavigationService.shared.location?.coordinate
            var addressHint = ""

            if let query, !query.isEmpty {
                let places = try await MapKitNavigationService.shared.searchPlaces(
                    query: query,
                    near: coordinate
                )
                if let first = places.first {
                    title = first.name
                    addressHint = first.address.isEmpty ? first.category : first.address
                    coordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
                } else {
                    return historical
                        ? "Nie znalazłem miejsca „\(query)” do opowiedzenia historii."
                        : "Nie znalazłem informacji o „\(query)”."
                }
            } else if let coordinate {
                let placemark = try await MapKitNavigationService.shared.reverseGeocode(coordinate: coordinate)
                title = [placemark.thoroughfare, placemark.subThoroughfare]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if title.isEmpty { title = placemark.locality ?? "" }
                addressHint = [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }

            guard !title.isEmpty else {
                return historical
                    ? "Nie wiem, o jakiej ulicy mówisz."
                    : "Brak lokalizacji do odczytu obecnej ulicy."
            }

            // Źródła: PRG/OGC + Nominatim + Wikipedia — wynik narracyjny, bez kodów
            var body: String
            if let coordinate,
               let knowledge = await PolishStreetKnowledgeService.lookup(
                   coordinate: coordinate,
                   preferredName: title,
                   wantCuriosity: true
               ) {
                title = knowledge.streetName
                if knowledge.hasCuriosity {
                    body = knowledge.cardBody
                } else if let chat = CoreLM.makeChatSession() {
                    let place = knowledge.narrativePlaceLabel
                    let district = knowledge.osmContext.map { " (okolica: \($0))" } ?? ""
                    let note = (try? await CoreLM.honestReply(
                        to: """
                        Opowiedz 2 krótkie zdania o miejscu „\(place)”\(district) w Polsce.
                        Skup się na ciekawostce historycznej, charakterze ulicy albo tym, czym jest wyjątkowa.
                        Pisz naturalnie, jak przewodnik w aucie. BEZ kodów, numerów TERYT/SIMC, kodów pocztowych i żargonu rejestrów.
                        Jeśli nie znasz pewnych faktów — powiedz to wprost, bez zmyślania dat.
                        """,
                        session: chat
                    )) ?? ""
                    body = note.isEmpty ? knowledge.cardBody : note
                } else {
                    body = knowledge.cardBody
                }
            } else if historical {
                if let chat = CoreLM.makeChatSession() {
                    let note = (try? await CoreLM.honestReply(
                        to: """
                        Podaj 2 zdania o historii lub charakterze miejsca „\(title)”\(addressHint.isEmpty ? "" : " (\(addressHint))") w Polsce.
                        Naturalnie, bez kodów i numerów. Jeśli nie jesteś pewien faktów — powiedz to wprost.
                        Nie zmyślaj dat ani wydarzeń.
                        """,
                        session: chat
                    )) ?? ""
                    body = note.isEmpty
                        ? "\(title). Nie mam pewnej historii tego miejsca."
                        : note
                } else {
                    body = "\(title)\(addressHint.isEmpty ? "" : ". \(addressHint)")."
                }
            } else if !addressHint.isEmpty {
                body = "\(title). \(addressHint)."
            } else {
                body = "Jesteś przy: \(title)."
            }

            DriveInfoCardStore.shared.present(.street(title: title, body: body, image: nil))
            if let coordinate {
                Task { @MainActor in
                    let photo = await AppleMapsPlaceVisuals.placePhoto(at: coordinate)
                    DriveInfoCardStore.shared.updateStreetImage(photo)
                }
            }
            return body
        } catch {
            return historical
                ? "Nie udało się pobrać historii ulicy."
                : "Nie udało się pobrać informacji o ulicy."
        }
    }

    private static func executeSetCarModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return "Powiedz model auta, na przykład: „moje auto to Toyota Corolla”."
        }
        let consumption = CarFuelEstimator.litersPer100km(forModel: trimmed)
        UserDefaults.standard.set(trimmed, forKey: "carModel")
        UserDefaults.standard.set(consumption, forKey: "fuelConsumptionLPer100")
        if consumption <= 0 {
            return "Zapisałem \(trimmed). To wygląda na auto elektryczne — koszt paliwa w litrach nie dotyczy."
        }
        return String(
            format: "Zapisałem model \(trimmed). Szacuję ok. %.1f l/100 km — użyję tego przy koszcie paliwa.",
            consumption
        )
    }

    private static func executeMusic(_ command: MusicPlaybackCommand) -> String {
        let player = MusicPlayerService.shared
        // Upewnij się, że biblioteka jest świeża (import w Settings).
        player.bind(library: MusicLibraryService.shared)
        MusicLibraryService.shared.load()

        guard player.hasTracks else {
            NotificationCenter.default.post(name: .driveMateDidControlMusic, object: nil)
            return "Nie mam utworów — dodaj muzykę w ustawieniach, wtedy steruję odtwarzaczem."
        }

        let reply: String
        switch command {
        case .pause:
            if !player.isPlaying {
                reply = "Muzyka już jest wstrzymana."
            } else {
                player.pause()
                reply = "Pauza."
            }

        case .resume:
            if player.play(), let name = player.currentTrack?.name {
                reply = "Wznawiam \(name)."
            } else {
                reply = "Nie udało się odtworzyć utworu."
            }

        case .toggle:
            player.togglePlayPause()
            reply = player.isPlaying
                ? (player.currentTrack.map { "Wznawiam \($0.name)." } ?? "Wznawiam muzykę.")
                : "Pauza."

        case .next:
            if player.next(andPlay: true), let name = player.currentTrack?.name {
                reply = "Następny utwór: \(name)."
            } else {
                reply = "Nie udało się przełączyć utworu."
            }

        case .previous:
            if player.previous(andPlay: true), let name = player.currentTrack?.name {
                reply = "Poprzedni utwór: \(name)."
            } else {
                reply = "Nie udało się przełączyć utworu."
            }
        }

        NotificationCenter.default.post(name: .driveMateDidControlMusic, object: nil)
        return reply
    }

    private static func executeRestoreInterruptedRoute() async -> String {
        guard let saved = InterruptedRouteStore.shared.route else {
            return "Nie mam zapisanej wcześniejszej trasy. Pojawi się, gdy przerwiesz nawigację np. zjazdem do restauracji albo stacji."
        }

        RestaurantOfferService.shared.dismiss()
        GasStationOfferService.shared.dismiss()
        MapComplianceStore.shared.clear()

        // Bez podsumowania / anulowania — tylko zmiana celu na wcześniejszy, start = aktualna lokalizacja.
        do {
            _ = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: saved.latitude,
                toLongitude: saved.longitude,
                destinationName: saved.title
            )
            NotificationCenter.default.post(
                name: .driveMateDidNavigate,
                object: nil,
                userInfo: [
                    "title": saved.title,
                    "subtitle": saved.subtitle,
                    "lat": saved.latitude,
                    "lon": saved.longitude,
                    "saveRecent": false,
                    "restoredRoute": true
                ]
            )
            InterruptedRouteStore.shared.clear()
            return "Przywracam wcześniejszą trasę do \(saved.title) — startuję z Twojej lokalizacji."
        } catch NavigationError.disclaimerRequired {
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return "Zaakceptuj warunki nawigacji, potem powiedz ponownie „przywróć wcześniejszą trasę”."
        } catch {
            return "Nie udało się przywrócić trasy do \(saved.title)."
        }
    }

    private static func executePastVisit(daysAgo: Int) async -> String {
        let memory = DriveMateMemoryStore.shared
        guard let visit = memory.visit(daysAgo: daysAgo) else {
            let label: String
            switch daysAgo {
            case 0: label = "dziś"
            case 1: label = "wczoraj"
            case 2: label = "przedwczoraj / 2 dni temu"
            default: label = "\(daysAgo) dni temu"
            }
            return "Nie mam zapisanego miejsca z okresu „\(label)” (pamiętam max 3 dni). Jedź dokądś, a zapamiętam."
        }
        do {
            InterruptedRouteStore.shared.snapshotActiveNavigationIfNeeded()
            _ = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: visit.latitude,
                toLongitude: visit.longitude,
                destinationName: visit.title
            )
            NotificationCenter.default.post(
                name: .driveMateDidNavigate,
                object: nil,
                userInfo: [
                    "title": visit.title,
                    "subtitle": visit.subtitle,
                    "lat": visit.latitude,
                    "lon": visit.longitude,
                    "saveRecent": true
                ]
            )
            let when: String
            switch daysAgo {
            case 0: when = "dziś"
            case 1: when = "wczoraj"
            case 2: when = "2 dni temu"
            default: when = "\(daysAgo) dni temu"
            }
            return "OK — prowadzę do \(visit.title) (miejsce z \(when))."
        } catch NavigationError.disclaimerRequired {
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            return "Zaakceptuj warunki nawigacji, potem powtórz komendę."
        } catch {
            return "Nie udało się wyznaczyć trasy do \(visit.title)."
        }
    }

    private static func executeChromeVisibility(query: String, visible: Bool) -> String {
        let lower = query.lowercased()
        if lower.contains("muzyk") || lower.contains("zakoncz") || lower.contains("zakończ")
            || lower.contains("skręt") || lower.contains("skret") || lower.contains("nawigacj") {
            return "Tego kafelka nie mogę ukryć — zakończ trasę, muzyka i skręt zawsze zostają."
        }
        guard let tile = DriveChromeTile.resolve(fromQuery: query) else {
            return "Nie rozpoznaję kafelka „\(query)”. Mogę: prędkościomierz, zegar, Drive, wyśrodkuj, nagrywanie."
        }
        let currentlyVisible = DriveChromeVisibilityStore.shared.isVisible(tile)
        if currentlyVisible == visible {
            return visible
                ? "\(tile.displayName.prefix(1).uppercased())\(tile.displayName.dropFirst()) już jest widoczny."
                : "\(tile.displayName.prefix(1).uppercased())\(tile.displayName.dropFirst()) już jest ukryty."
        }
        return DriveChromeVisibilityStore.shared.setVisible(tile, visible: visible)
    }

    private static func executeFuelCost() -> String {
        guard let mapState = MapKitNavigationService.shared.mapState,
              mapState.isNavigating,
              let route = mapState.route else {
            return "Nie mam aktywnej trasy — najpierw wyznacz dojazd, wtedy oszacuję paliwo."
        }

        let carModel = (UserDefaults.standard.string(forKey: "carModel") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var consumption = UserDefaults.standard.double(forKey: "fuelConsumptionLPer100")
        if consumption <= 0, !carModel.isEmpty {
            consumption = CarFuelEstimator.litersPer100km(forModel: carModel)
        }

        guard !carModel.isEmpty, consumption > 0 else {
            return "Nie znam Twojego auta. Powiedz np. „moje auto to Toyota Corolla” albo wpisz model w Ustawieniach — wtedy policzę spalanie dokładnie."
        }

        let km = route.distance / 1000
        let liters = km * (consumption / 100)
        let cost = liters * CarFuelEstimator.defaultFuelPricePLNPerLiter

        DriveInfoCardStore.shared.present(
            .fuelCost(
                distanceKm: km,
                liters: liters,
                costPLN: cost,
                carModel: carModel,
                consumptionLPer100: consumption
            )
        )

        return String(
            format: "Trasa ma ok. %.1f km. Dla \(carModel) (%.1f l/100 km) to około %.1f l, czyli około %.0f zł.",
            km, consumption, liters, cost
        )
    }

    private static func executeNearestFuel(preferCheapest: Bool) async -> String {
        guard let coordinate = MapKitNavigationService.shared.location?.coordinate else {
            return "Brak lokalizacji — nie znajdę stacji paliw."
        }
        let interrupting = MapKitNavigationService.shared.mapState?.isNavigating == true
        return await GasStationOfferService.shared.findAndPresent(
            near: coordinate,
            preferCheapest: preferCheapest,
            interruptingActiveRoute: interrupting
        )
    }

    private static func executeNavigate(destination: String, start: NavigateStartOrigin?) async -> String {
        // Konfiguracja trasy — bez mini-mapki podglądu.
        MapComplianceStore.shared.clear()
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
                // Always Use My Location — od razu GPS, bez pytania
                if UserDefaults.standard.bool(forKey: "alwaysUseMyLocation") {
                    return await startRoute(
                        to: first,
                        fromLatitude: nil,
                        fromLongitude: nil,
                        startLabel: "Twojej lokalizacji"
                    )
                }
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
            InterruptedRouteStore.shared.snapshotActiveNavigationIfNeeded()
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
                InterruptedRouteStore.shared.snapshotActiveNavigationIfNeeded()
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
            InterruptedRouteStore.shared.snapshotActiveNavigationIfNeeded()
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
            "moja lokalizacja", "mojej lokalizacji", "mojej lokalizacja", "moja lokalizaca",
            "swojej lokalizacji", "swoja lokalizacja", "ze swojej lokalizacji",
            "skorzystaj z mojej lokalizacji", "skorzystaj z lokalizacji",
            "uzyj mojej lokalizacji", "uzyj lokalizacji",
            "z mojej lokalizacji", "z swojej lokalizacji", "z lokalizacji",
            "mojego punktu", "z mojego punktu", "moj punkt",
            "tu gdzie jestem", "tutaj gdzie jestem", "tam gdzie jestem",
            "z tutaj", "stad", "z stad",
            "obecna lokalizacja", "biezaca lokalizacja",
            "gps", "moja pozycja", "z mojej pozycji", "moja pozycja gps",
            "my location", "current location", "use my location",
            "from here", "here", "use gps", "start from here"
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
