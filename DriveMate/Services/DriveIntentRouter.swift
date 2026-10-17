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
    /// Najbliższy sklep sieci (Żabka, Lewiatan, Empik…). `query` = fraza MapKit, `label` = nazwa do mowy.
    case findNearestStore(query: String, label: String)
    /// Losowa ciekawostka (nie o ulicy).
    case tellTrivia
    case cancelListening
    case cancelRoute
    /// Przywróć trasę przerwaną przez zjazd (restauracja / stacja / nowa nawigacja).
    case restoreInterruptedRoute
    case music(MusicPlaybackCommand)
    case speedLimit
    /// Ile paliwa / ile złotych na aktywnej trasie.
    case fuelCost
    /// Stan baku: ile litrów, jaki procent, czy wystarczy.
    case fuelLevel
    /// Na ile kilometrów wystarczy obecne paliwo (i czy dowiezie do celu).
    case fuelRange
    /// Najbliższa stacja; `preferCheapest` = szukaj pod kątem ceny (bez live cen MapKit — ranking dystansu + informacja).
    case nearestFuel(preferCheapest: Bool)
    /// „Gdzie jestem” — odczyt obecnego adresu i nazwy ulicy.
    case whereAmI
    /// Zapis modelu auta (np. „Toyota Corolla”).
    case setCarModel(String)
    /// Nawigacja do miejsca odwiedzonego N dni temu (0 = dziś).
    case navigateToPastVisit(daysAgo: Int)
    /// Ukryj / pokaż kafelek UI nawigacji.
    case setChromeTile(tileQuery: String, visible: Bool)
    /// Wyśrodkuj mapę / widok na lokalizacji kierowcy.
    case recenterMap
    /// Pokaż okienko z listą umiejętności Drive Mate.
    case showCapabilities
    /// Luźna odpowiedź (wiedza / rozmowa) — bez efektów mapy.
    case answer(replyHint: String)
    /// Funkcja spoza możliwości — uczciwa odmowa.
    case unsupported(replyHint: String)
    case unknown(raw: String)
}

enum DriveIntentParser {
    /// Dopasowanie bez polskich znaków — ASR często gubi diakrytyki.
    /// Używa wspólnego fold(), który poprawnie zamienia też „ł” (patrz DriveIntentQueryHelpers).
    private static func folded(_ text: String) -> String {
        DriveIntentQueryHelpers.foldForMatching(text)
    }

    @MainActor
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

        // Wyśrodkuj widok mapy PRZED chrome — „pokaż mnie na mapie” / „wyśrodkuj” ≠ ukryj/pokaż kafelek
        if isRecenterMap(lower) {
            return .recenterMap
        }

        // Ukryj / pokaż kafelki UI
        if let chrome = extractChromeVisibility(from: lower) {
            return .setChromeTile(tileQuery: chrome.query, visible: chrome.visible)
        }

        // „Co potrafisz?” → okienko umiejętności
        if isCapabilitiesHelp(lower) {
            return .showCapabilities
        }

        // „Gdzie jestem” / „jaki jest mój adres” — najczęstsze pytanie, wyprzedza info o ulicy
        if isWhereAmI(lower) {
            return .whereAmI
        }

        // Ogólna ciekawostka (przed historią ulicy — „powiedz ciekawostkę” ≠ ulica)
        if isTriviaRequest(lower) {
            return .tellTrivia
        }

        // Historia ulicy (przed ogólnym streetInfo)
        if isStreetHistory(lower) {
            if isAboutCurrentPlace(lower) {
                return .streetHistory(query: nil)
            }
            let query = extractStreetQuery(cleaned, kind: .history)
            return .streetHistory(query: query)
        }

        // Korki / ryzyko (przed nawigacją — „korki na …” nie ma być trasą)
        if isTraffic(lower) {
            // „jak wygląda ruch na tej ulicy” — pytanie o TUTAJ, nie wyszukiwanie
            // ulicy o nazwie „tej ulicy” (wcześniej leciało „tej ulicy” do MapKit).
            if isAboutCurrentPlace(lower) {
                return .traffic(query: nil)
            }
            let query = extractStreetQuery(cleaned, kind: .traffic)
            return .traffic(query: query)
        }

        // Info o ulicy / miejscu
        if isStreetInfo(lower) {
            if isAboutCurrentPlace(lower) {
                return .streetInfo(query: nil)
            }
            let query = extractStreetQuery(cleaned, kind: .info)
            return .streetInfo(query: query ?? cleaned)
        }

        // Prędkość — po paliwie, bo „ile mogę jechać” myli się ze spalaniem
        if isSpeedLimit(lower) { return .speedLimit }

        // Paliwo: zasięg → koszt/zużycie trasy → stan baku → stacja.
        // Koszt PRZED poziomem — „ile mi to paliwa zużyje ta trasa” ≠ bak cyfrowy.
        if isFuelRange(lower) { return .fuelRange }
        if isFuelCost(lower) { return .fuelCost }
        if isFuelLevel(lower) { return .fuelLevel }
        if isNearestFuel(lower) {
            return .nearestFuel(preferCheapest: isCheapestFuel(lower))
        }

        // Jedzenie / głód
        if isFoodRequest(lower) {
            return .findFood
        }

        // Sklepy: Żabka, Lewiatan, Empik, Sinsay…
        if let store = extractStoreSearch(from: lower) {
            return .findNearestStore(query: store.query, label: store.label)
        }

        // Nawigacja z startem + celem w jednej wypowiedzi
        if let combo = extractNavigateWithStart(cleaned, lower: lower) {
            return combo
        }

        // Nawigacja / trasa (tylko cel)
        if isNavigation(lower) {
            if let dest = extractDestination(cleaned), dest.count > 1,
               !looksLikeUIOrCommandDestination(dest) {
                return .navigate(destination: dest, start: nil)
            }
            if let dest = stripNavigationPrefix(cleaned), dest.count > 1,
               !looksLikeUIOrCommandDestination(dest) {
                return .navigate(destination: dest, start: nil)
            }
        }

        // Szum / wypełniacze („yhm”, „aha”) — NIGDY nawigacja.
        if isNoiseOrFiller(lower) {
            return .unsupported(replyHint: Self.unknownCommandReply)
        }

        // Krótka nazwa miejsca TYLKO z wyraźnym hintem miejsca (np. „Rynek Dębnicki”).
        // Bez tego „yhm” / losowe słowa nie stają się celem trasy.
        if isBarePlaceName(cleaned, lower: lower) {
            return .navigate(destination: cleaned, start: nil)
        }

        // Semantyka — tylko gdy fraza wygląda na domenę Drive Mate (nie zgaduj nawigacji).
        if looksLikeKnownDomain(lower), let semantic = semanticFallback(cleaned) {
            return semantic
        }

        return .unknown(raw: cleaned)
    }

    /// Krótka odmowa — bez listy umiejętności (ta jest tylko po „co potrafisz”).
    static let unknownCommandReply = "Nie mogę tego zrealizować."

    /// Wypełniacze ASR / potwierdzenia bez treści komendy.
    static func isNoiseOrFiller(_ lower: String) -> Bool {
        let trimmed = lower
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return true }
        let fillers: Set<String> = [
            "yhm", "uhm", "um", "hmm", "hm", "mhm", "mm", "mmm", "ee", "eee", "yyy",
            "aha", "ano", "no", "noo", "nu", "ojoj", "ech", "ach", "och",
            "ok", "okay", "okej", "okey", "dobra", "dobrze", "jasne", "spoko",
            "tak", "nie", "yes", "yeah", "yep", "nope",
            "hej", "hey", "cześć", "czesc", "siema", "elo"
        ]
        if fillers.contains(trimmed) { return true }
        // Samogłoski / bełkot 1–3 znaki bez sensu miejsca
        if trimmed.count <= 3, trimmed.rangeOfCharacter(from: .decimalDigits) == nil {
            let letters = trimmed.filter(\.isLetter)
            if letters.count == trimmed.count, !hasPlaceHint(trimmed) {
                return true
            }
        }
        return false
    }

    private static func hasPlaceHint(_ lower: String) -> Bool {
        let placeHints = [
            "rynek", "ulic", "park", "plac", "kosciol", "dworzec", "centrum",
            "galeria", "most", "osiedle", "stadion", "lotnisko", "szpital", "muzeum",
            "wawel", "sukiennic", "mlynowka", "rondo", "skrzyz"
        ]
        return placeHints.contains(where: { lower.contains($0) })
    }

    /// Czy wypowiedź w ogóle należy do domeny komend Drive Mate.
    private static func looksLikeKnownDomain(_ lower: String) -> Bool {
        if isNoiseOrFiller(lower) { return false }
        if isNavigation(lower) || isTraffic(lower) || isStreetInfo(lower) || isStreetHistory(lower) { return true }
        if isFuelLevel(lower) || isFuelRange(lower) || isFuelCost(lower) || isNearestFuel(lower) { return true }
        if isFoodRequest(lower) || isSpeedLimit(lower) || isWhereAmI(lower) { return true }
        if isTriviaRequest(lower) || extractStoreSearch(from: lower) != nil { return true }
        if isRecenterMap(lower) || isCapabilitiesHelp(lower) { return true }
        if extractMusicCommand(from: lower) != nil { return true }
        if isCancelRoute(lower) || isCancelListening(lower) || isRestoreInterruptedRoute(lower) { return true }
        let domainKeys = [
            "paliw", "trase", "trasa", "nawig", "kork", "ulic", "adres", "restaur",
            "stacj", "tankow", "muzyk", "utwor", "piosenk", "wysrodk", "centruj",
            "potrafisz", "umiesz", "gdzie jestem", "ile mam", "dowiez"
        ]
        return domainKeys.contains(where: { lower.contains($0) })
    }

    /// Podobieństwo semantyczne jako ostatnia szansa przed CoreLM.
    /// NIE nadpisuje trafień słownikowych — tylko wypełnia luki.
    @MainActor
    static func semanticFallback(_ cleaned: String) -> DriveIntent? {
        guard DriveSemanticMatcher.isAvailable else { return nil }
        let mapState = MapKitNavigationService.shared.mapState
        let context = DriveSemanticMatcher.MatchContext(
            isNavigating: mapState?.isNavigating == true,
            isAskingAboutCurrentPlace: isAboutCurrentPlace(folded(cleaned))
        )
        return DriveSemanticMatcher.match(cleaned, context: context)?.intent
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

    /// „Wyśrodkuj mi widok” / „centruj mapę” — akcja UI, nie nawigacja do „widok”.
    private static func isRecenterMap(_ lower: String) -> Bool {
        let phrases = [
            "wysrodkuj", "wysrodkowac", "wycentruj", "wycentrowac", "centruj",
            "recenter", "center map", "centre map",
            "pokaz mnie na mapie", "pokaz mnie", "gdzie jestem na mapie"
        ]
        guard phrases.contains(where: { lower.contains($0) }) else { return false }
        // „ukryj przycisk wyśrodkuj” / „schowaj kafelek wyśrodkuj” = chrome, nie akcja mapy
        let chromeOnly = lower.contains("kafelek") || lower.contains("przycisk")
        if chromeOnly && (
            lower.contains("ukryj") || lower.contains("schowaj")
                || lower.contains("wylacz") || lower.contains("wlacz")
                || lower.contains("pokaz")
        ) {
            return false
        }
        return true
    }

    /// Naturalne pytania o możliwości Drive Mate.
    private static func isCapabilitiesHelp(_ lower: String) -> Bool {
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let exact = ["pomoc", "pomocy", "help", "umiejetnosci", "funkcje"]
        if exact.contains(trimmed) { return true }

        let phrases = [
            "co potrafisz", "co umiesz", "co potraficie", "co umiecie",
            "co potrafisz zrobic", "co umiesz zrobic", "co potrafisz robic",
            "jakie masz umiejetnosci", "jakie sa twoje umiejetnosci",
            "jakie umiejetnosci masz", "jakie masz funkcje", "jakie funkcje masz",
            "co mozesz", "co mozesz zrobic", "co mozna zrobic",
            "czym mozesz pomoc", "czym mozesz mi pomoc", "w czym mozesz pomoc",
            "w czym pomagasz", "jak mozna cie uzywac", "jak cie uzywac",
            "what can you do", "what do you do",
            "lista komend", "jakie komendy", "dostepne komendy",
            "co drive mate umie", "co drivemate umie", "co umie drive mate",
            "powiedz co umiesz", "powiedz co potrafisz", "pokaz umiejetnosci"
        ]
        if phrases.contains(where: { trimmed.contains($0) }) { return true }
        // „co ty umiesz”, „powiedz co potrafisz”
        if (trimmed.contains("umiesz") || trimmed.contains("potrafisz") || trimmed.contains("mozesz"))
            && (trimmed.contains("co ") || trimmed.hasPrefix("co") || trimmed.contains("jakie")) {
            // Unikaj „co mogę jechać” / pytań o mapę — tam nie ma „umiesz/potrafisz”.
            return true
        }
        return false
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
        // `lower` jest już folded, więc „następny” → „nastepny”. Klucz z „ę” nigdy nie trafiał.
        let wantsNext = lower.contains("nastepn") || lower.contains("kolejn") || lower.contains("skip")
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
            "speed limit", "ile max", "max predkosci",
            "jaka jest predkosc", "ile tutaj moge", "jak szybko moge",
            "jakie ograniczenie", "ograniczenie predkosci", "znak ograniczenia",
            "dopuszczalna predkosc", "predkosciomierz"
        ]
        if keys.contains(where: { lower.contains($0) }) { return true }
        let asksSpeed = lower.contains("ile") || lower.contains("jak")
        let speedWord = lower.contains("moge") || lower.contains("mozna") || lower.contains("wolno")
            || lower.contains("predkosci") || lower.contains("predkosc")
        let aboutFuel = lower.contains("paliw") || lower.contains("litr") || lower.contains("litro")
        return asksSpeed && speedWord && !aboutFuel
    }

    // MARK: - Paliwo

    /// Słowa o paliwie / baku — wspólne dla fuelLevel, fuelRange i nearestFuel.
    private static func hasFuelVocabulary(_ lower: String) -> Bool {
        let words = [
            "paliw", "paliv", "benzyn", "diesel", "olej napedy", "lpg",
            "bak", "baku", "tankow", "zatankow", "nalew",
            "fuel", "petrol", "litro", "litr", "spalan", "spale",
            "zuzyc", "zuzyj", "zuzywa", "zasieg", "rezerw"
        ]
        return words.contains { lower.contains($0) }
    }

    /// Zużycie / spalanie na trasie (nie poziom w baku).
    private static func mentionsRouteFuelBurn(_ lower: String) -> Bool {
        let burn = lower.contains("zuzyj") || lower.contains("zuzywa") || lower.contains("zuzyc")
            || lower.contains("spalan") || lower.contains("spal ") || lower.contains("spale")
            || lower.contains("spalimy") || lower.contains("wypali") || lower.contains("wyjdzie")
        let onRoute = lower.contains("tras") || lower.contains("przejazd") || lower.contains("dojazd")
            || lower.contains("do celu") || lower.contains("na tej") || lower.contains("ta trasa")
        if burn { return true }
        // „ile paliwa na trasie” / „ile mi to paliwa … trasa”
        if onRoute && (lower.contains("paliw") || lower.contains("paliv") || lower.contains("litr")) {
            return true
        }
        return false
    }

    /// Wyszukiwanie stacji paliw (nie stan baku, nie koszt).
    private static func isStationSearch(_ lower: String) -> Bool {
        let keys = [
            "stacja paliw", "stacje paliw", "stacji paliw", "stacja paliwo", "stacje paliw",
            "stacja benzyn", "stacje benzyn", "stacji benzyn",
            "najblizsza stacja", "najblizsze stacje", "najblizszy orlen", "najblizsza benzyn",
            "gdzie stacja", "gdzie zatankowac", "gdzie natankowac", "gdzie nalewac",
            "gdzie tankowac", "szukaj stacji", "znajdz stacje", "pokaz stacje",
            "szukam stacji", "trzeba zatankowac", "musze zatankowac",
            "chce zatankowac", "potrzebuje stacji", "na ktorej stacji",
            // „gdzie najtaniej zatankować” — poprzednio wypadało na .unknown,
            // bo tabela miała tylko „gdzie zatankowac”, a nie „gdzie … zatankowac”.
            "gdzie najtaniej", "gdzie najtansz", "gdzie najlepsz", "gdzie taniej",
            "gdzie najtaniej zatankowac", "gdzie zatankowac najtaniej",
            "orlen", "shell", "bp ", "lotos", "circlek", "avia",
            "gas station", "petrol station", "fuel station"
        ]
        return keys.contains { lower.contains($0) }
    }

    private static func mentionsCostOrBurn(_ lower: String) -> Bool {
        lower.contains("paliw") || lower.contains("paliv") || lower.contains("benzyn")
            || lower.contains("spalan") || lower.contains("spal") || lower.contains("zuzyc")
            || lower.contains("litr") || lower.contains("litro") || lower.contains("fuel")
    }

    private static func mentionsTankState(_ lower: String) -> Bool {
        lower.contains("baku") || lower.contains("bak ") || lower.contains("poziom")
            || lower.contains("ile") || lower.contains("wystarcz") || lower.contains("starcz")
            || lower.contains("musz") || lower.contains("stan")
    }

    private static func mentionsRange(_ lower: String) -> Bool {
        lower.contains("zasieg") || lower.contains("dojade") || lower.contains("pojade")
            || lower.contains("dowiez") || lower.contains("wystarczy") || lower.contains("starczy")
            || lower.contains("daleko") || lower.contains("rezerw")
    }

    /// Jednoznaczne pytanie o KOSZT. Rozdziela „ile paliwa zostało” od
    /// „ile kosztuje przejazd paliwem” — oba zaczynają się od „ile paliwa”.
    private static func mentionsPriceOrCost(_ lower: String) -> Bool {
        let costWords = [
            "koszt", "cena", "cene", "ceny", "tanie", "tania", "tansz",
            "zaplac", "zapłac", "wydam", "wyjdzie", "kosztow", "drogo",
            "ile zl", "za ile"
        ]
        if costWords.contains(where: { lower.contains($0) }) { return true }
        // „ile litrów zużyjemy” / „ile mi to paliwa zużyje ta trasa” — zużycie, nie bak
        if mentionsRouteFuelBurn(lower) {
            return !mentionsTankStateExplicitly(lower)
        }
        return false
    }

    /// Stan baku powiedziany Wprost — ma pierwszeństwo przed kosztem.
    /// Np. „ile litrów mam w baku” (poziom) vs. „ile litrów zużyjemy” (koszt).
    private static func mentionsTankStateExplicitly(_ lower: String) -> Bool {
        let keys = [
            "w baku", "w moim baku", "w mojej baku", "w naszym baku",
            "mam paliwa", "mam benzyny", "mam w baku", "mam litrow w",
            "zostalo", "zostało", "stan paliwa", "stan baku",
            "poziom", "procent", "bak pelny", "bak pełny", "bak napelniony",
            "bak napełniony", "czy bak", "czy musze", "czy starczy", "czy wystarczy",
            "czy wystarczy mi", "musze zatankowac", "musze tankowac", "przed tankowaniem"
        ]
        return keys.contains(where: { lower.contains($0) })
    }

    /// Stan baku — „ile mam paliwa”, „czy wystarczy”, „czy muszę tankować”.
    private static func isFuelLevel(_ lower: String) -> Bool {
        // Zużycie na trasie NIGDY nie jest stanem baku (nawet przy „ile paliwa”).
        if mentionsRouteFuelBurn(lower) { return false }

        // „czy starczy mi tego na trasę” — wskazanie „tego” odnosi się do paliwa,
        // ale w samej wypowiedzi nie ma go zapisanego (wcześniej → .unknown).
        let anaphoric = [
            "czy starczy mi tego", "czy wystarczy mi tego", "czy starczy tego",
            "czy wystarczy tego", "starczy tego na tras", "wystarczy tego na tras",
            "czy starczy mi na tras", "czy wystarczy mi na tras"
        ]
        if anaphoric.contains(where: { lower.contains($0) }) { return true }

        guard hasFuelVocabulary(lower) else { return false }
        // „ile kosztuje przejazd paliwem” / „ile zapłacę za benzynę” to koszt, nie stan.
        if mentionsPriceOrCost(lower) { return false }
        if isStationSearch(lower) && !mentionsTankState(lower) { return false }

        let keys = [
            "ile mam paliwa", "ile mam benzyny", "ile paliwa mam", "ile paliwa zostalo",
            "ile paliwa zostało", "ile litrow mam", "ile litrow w baku",
            "ile litrow zostalo", "ile litrow zostało", "poziom paliwa", "poziomu paliwa",
            "stan paliwa", "paliwo w baku", "paliwa w baku",
            "w baku", "w moim baku", "bak napełniony", "bak napelniony", "bak pelny", "bak pełny",
            "czy bak", "ile procent paliwa", "jaki procent paliwa", "procent paliwa",
            "czy starczy", "czy wystarczy mi paliwa", "czy wystarczy mi tego", "czy wystarczy paliwa",
            "czy starczy paliwa", "czy wystarczy na trasę", "czy wystarczy na trase",
            "czy musze zatankowac", "czy musze tankowac", "musze zatankowac",
            "powinienem zatankowac", "przed tankowaniem", "przy tankowac",
            "moj bak", "moje auto ma ile",
            "how much fuel do i have", "fuel level", "how much fuel is left", "do i need to refuel"
        ]
        // Świadomie BEZ gołego „ile paliwa” — to też „ile paliwa zużyje trasa”.
        if keys.contains(where: { lower.contains($0) }) { return true }

        // „ile paliwa” tylko przy kontekście baku / poziomu (nie trasy).
        if lower.contains("ile paliwa") || lower.contains("ile paliva") {
            return mentionsTankStateExplicitly(lower)
                || lower.contains("mam") || lower.contains("zostal") || lower.contains("poziom")
                || lower.contains("procent") || lower.contains("baku") || lower.contains("bak")
        }

        let asksState = lower.contains("ile") || lower.contains("jak duzo") || lower.contains("jaki procent")
            || lower.contains("czy") || lower.contains("wystarcz") || lower.contains("starcz")
            || lower.contains("musz") || lower.contains("powinien") || lower.contains("stan")
        let aboutTank = lower.contains("baku") || lower.contains("bak ")
            || (lower.contains("paliw") && mentionsTankStateExplicitly(lower))
        return asksState && aboutTank
    }

    /// Zasięg — „na ile wystarczy”, „dowieziesz mnie”, „jak daleko dojadę”.
    private static func isFuelRange(_ lower: String) -> Bool {
        // Zasięg bywa zadawany bez słowa „paliwo”: „jak daleko dojadę”,
        // „dowieziesz mnie do celu”, „na ile kilometrów wystarczy”.
        let explicitRange = [
            "na ile wystarczy", "na ile kilometrow wystarczy", "na ile starczy",
            "na ile mam", "jak daleko dojade", "jak daleko pojade",
            "jak daleko wystarczy", "jakie mam zasięgi",
            "ile kilometrow dojade", "ile kilometrow pojade",
            "dowieziesz mnie", "dowiezie mnie",
            "dojade na rezerw", "pojade na rezerw", "wystarczy na rezerw",
            "wystarczy do konca trasy", "wystarczy do celu", "dowiezie do celu",
            "czy dojade", "czy pojade",
            "range", "how far can i", "will i make it"
        ]
        if explicitRange.contains(where: { lower.contains($0) }) { return true }

        guard hasFuelVocabulary(lower) else { return false }
        if isStationSearch(lower) && !mentionsRange(lower) { return false }

        let keys = [
            "zasieg auta", "zasieg mojego auta", "zasieg samochodu", "zasieg przy",
            "zasieg", "jak daleko", "dowieziesz", "dowiezie",
            "do konca trasy", "do celu"
        ]
        return keys.contains(where: { lower.contains($0) })
    }

    /// Koszt / zużycie paliwa na trasie.
    private static func isFuelCost(_ lower: String) -> Bool {
        if isStationSearch(lower) && !mentionsCostOrBurn(lower) && !mentionsRouteFuelBurn(lower) {
            return false
        }
        // „ile litrów mam w baku” pyta o poziom, nie o koszt — chyba że to zużycie trasy.
        if mentionsTankStateExplicitly(lower) && !mentionsPriceOrCost(lower) && !mentionsRouteFuelBurn(lower) {
            return false
        }
        guard hasFuelVocabulary(lower) || mentionsRouteFuelBurn(lower) else { return false }

        if mentionsRouteFuelBurn(lower) { return true }

        let keys = [
            "ile paliwa", "ile paliva", "ile spal", "ile spale", "ile spalimy", "ile zuzyje",
            "ile mi to paliwa", "paliwa zuzyje", "paliwa zuzywa", "zuzyje ta trasa",
            "ile wyjdzie", "ile wyjdzie paliwa", "ile wyjdzie z trasy", "paliwa z trasy",
            "koszt paliwa", "koszt paliva", "koszt przejazdu", "koszt trasy", "cena przejazdu",
            "ile bedzie kosztowac", "ile bedzie koszt", "ile to bedzie kosztowac",
            "ile bedzie kosztowalo", "ile zaplace", "ile zaplace za paliwo", "ile zl paliwo",
            "zuzycie paliwa", "zuzycie paliva", "zuzycie na trasie", "zusycie paliwa",
            "ile litrow", "ile litrow zuzyje", "spalanie", "spalanie na trasie", "spalanie paliwa",
            "koszt dojazdu", "ile zl bedzie", "ile zl zaplacimy", "ile zaplacimy",
            "za ile bede", "za ile bedziemy", "za ile zaplacze", "tankowanie bedzie kosztowac",
            "ile litrow na trasie", "paliwo na trasie", "koszt dojazdu paliwem",
            "spale na trasie", "spalę na trasie", "spali na trasie", "zuzyjesz",
            "ile wypali", "ile wydam na paliwo", "ile wydam na benzyne",
            "fuel cost", "fuel consumption", "how much fuel", "gas cost", "how much will it cost"
        ]
        if keys.contains(where: { lower.contains($0) }) { return true }

        let asksQuantity = lower.contains("ile") || lower.contains("koszt") || lower.contains("cena")
            || lower.contains("spal") || lower.contains("zuzyj") || lower.contains("zuzyc")
            || lower.contains("litr")
            || lower.contains("zaplace") || lower.contains("wypali")
            || lower.contains("wydam") || lower.contains("wyjdzie") || lower.contains("kosztowac")
        return asksQuantity && mentionsCostOrBurn(lower)
    }

    private static func isNearestFuel(_ lower: String) -> Bool {
        if isStationSearch(lower) { return true }
        // „gdzie najtaniej zatankować” — sama stacja nie jest nazwana.
        if lower.contains("zatankow") || lower.contains("tankow") || lower.contains("nalew") {
            return isCheapestFuel(lower) || lower.contains("gdzie") || lower.contains("szukaj")
                || lower.contains("znajdz") || lower.contains("blisko") || lower.contains("okolic")
        }
        return lower.contains("benzyn") && (
            lower.contains("najbliz") || lower.contains("gdzie") || lower.contains("szukaj")
                || lower.contains("znajdz") || lower.contains("okolic") || lower.contains("w poblizu")
        )
    }

    private static func isCheapestFuel(_ lower: String) -> Bool {
        // Uwaga: po foldzie „najtańsze” → „najtansze”, więc „najtani” NIE występuje
        // jako podciąg (najtan-s-ze). Trzeba szukać „najtansz” / „tansz”.
        lower.contains("najtansz") || lower.contains("najtani") || lower.contains("tansz")
            || lower.contains("najlepsz") || lower.contains("tanio")
            || lower.contains("cena") || lower.contains("cene") || lower.contains("ceny")
            || lower.contains("tansza") || lower.contains("tańsza")
            || lower.contains("cheapest") || lower.contains("best price")
    }

    // MARK: - Ulica / miejsce

    /// Czy mowa o miejscu, w którym kierowca jest TERAZ.
    private static func isAboutCurrentPlace(_ lower: String) -> Bool {
        lower.contains("obec") || lower.contains("obecn") || lower.contains("tutaj")
            || lower.contains("tuz") || lower.contains("tu ") || lower.hasPrefix("tu ")
            || lower.contains("ta ulic") || lower.contains("te ulic") || lower.contains("ta ulice")
            || lower.contains("tej ulic") || lower.contains("tutaj ulic")
            || lower.contains("w ktorym jestem") || lower.contains("na ktorej jestem")
    }

    private static func isTriviaRequest(_ lower: String) -> Bool {
        // Ogólna ciekawostka — nie o konkretnej ulicy / miejscu.
        if lower.contains("ulic") || lower.contains("tej drog") || lower.contains("tym miejsc")
            || lower.contains("tej miejsc") || lower.contains("o tej") || lower.contains("o ulic") {
            return false
        }
        let keys = [
            "jakas ciekawostk", "jakąś ciekawostk", "jakas ciekawa", "ciekawa historie",
            "powiedz ciekawostk", "opowiedz ciekawostk", "daj ciekawostk", "chce ciekawostk",
            "chcialbym ciekawostk", "powiedz mi ciekawostk", "opowiedz mi ciekawostk",
            "powiedz cos ciekawego", "powiedz coś ciekawego", "cos ciekawego",
            "jakaś ciekawostka", "jakas ciekawostka", "ciekawostke", "ciekawostkę",
            "tell me a fun fact", "fun fact", "random fact", "ciekawostka losowa"
        ]
        return keys.contains(where: { lower.contains($0) })
    }

    private static func isStreetHistory(_ lower: String) -> Bool {
        let historyWord = lower.contains("histori") || lower.contains("ciekawostk")
            || lower.contains("skad nazwa") || lower.contains("skąd nazwa")
            || lower.contains("od kiedy") || lower.contains("kiedy zbudowano")
            || lower.contains("co sie tu dzieje") || lower.contains("co się tu dzieje")
            || lower.contains("co tu bylo") || lower.contains("co tu było")
            || lower.contains("tlumaczenie nazwy") || lower.contains("co oznacza ta nazwa")
            || lower.contains("pochodzenie nazwy") || lower.contains("geneza")
        guard historyWord else { return false }
        // Wymagaj kontekstu ulicy/miejsca — sama „ciekawostka” idzie do tellTrivia.
        return lower.contains("ulic") || lower.contains("miejsc") || lower.contains("drog")
            || lower.contains("tej") || isAboutCurrentPlace(lower)
            || lower.contains(" ta ") || lower.contains("o ulic") || lower.contains("o tej")
    }

    /// Żabka / Lewiatan / Empik / Sinsay / inne sieci — szukaj najbliższej od GPS.
    private static func extractStoreSearch(from lower: String) -> (query: String, label: String)? {
        let brands: [(keys: [String], query: String, label: String)] = [
            (["zabka", "żabka", "zabke", "żabkę", "zabki", "żabki"], "Żabka", "Żabka"),
            (["lewiatan"], "Lewiatan", "Lewiatan"),
            (["empik"], "Empik", "Empik"),
            (["sinsay"], "Sinsay", "Sinsay"),
            (["biedronk"], "Biedronka", "Biedronka"),
            (["lidl"], "Lidl", "Lidl"),
            (["auchan"], "Auchan", "Auchan"),
            (["carrefour", "karfur"], "Carrefour", "Carrefour"),
            (["rossmann", "rosman"], "Rossmann", "Rossmann"),
            (["hebe"], "Hebe", "Hebe"),
            (["pepco"], "Pepco", "Pepco"),
            (["reserved"], "Reserved", "Reserved"),
            (["house "], "House", "House"),
            (["cropp"], "Cropp", "Cropp"),
            (["ccc "], "CCC", "CCC"),
            (["media markt", "mediamarkt"], "Media Markt", "Media Markt"),
            (["rtv euro", "euro agd"], "RTV Euro AGD", "RTV Euro AGD"),
            (["ikea"], "IKEA", "IKEA"),
            (["castorama", "kastorama"], "Castorama", "Castorama"),
            (["leroy merlin", "leroy"], "Leroy Merlin", "Leroy Merlin"),
            (["albinka", "albi "], "Albi", "Albi"),
            (["dealz"], "Dealz", "Dealz"),
            (["action"], "Action", "Action"),
            (["primark"], "Primark", "Primark"),
            (["hm ", "h&m", "h and m"], "H&M", "H&M"),
            (["zara"], "Zara", "Zara"),
            (["reserved"], "Reserved", "Reserved"),
            (["apteka"], "apteka", "apteka"),
            (["kiosk"], "kiosk", "kiosk")
        ]

        let wantsNearest = lower.contains("najbliz") || lower.contains("najbliż")
            || lower.contains("znajdz") || lower.contains("znajdź") || lower.contains("szukaj")
            || lower.contains("gdzie jest") || lower.contains("gdzie mam") || lower.contains("poprowad")
            || lower.contains("jedz do") || lower.contains("jedź do") || lower.contains("do ")
            || lower.contains("pokaz") || lower.contains("pokaż") || lower.contains("kieruj")

        for brand in brands {
            guard brand.keys.contains(where: { lower.contains($0.trimmingCharacters(in: .whitespaces)) }) else {
                continue
            }
            // „Żabka” samo w nawigacji też OK — ale unikaj czystego brandu bez kontekstu szukania
            // gdy to może być nazwa ulicy; przy jawnych czasownikach zawsze sklep.
            if wantsNearest || lower.contains("sklep") || lower.contains("market") {
                return (brand.query, brand.label)
            }
            // Samo „żabka” / „najbliższa żabka” po foldzie
            if lower.hasPrefix(brand.keys[0]) || lower == brand.keys[0]
                || brand.keys.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
                return (brand.query, brand.label)
            }
            // „znajdź żabkę”, „jedź do empiku”
            if wantsNearest || lower.contains(brand.label.lowercased()) {
                return (brand.query, brand.label)
            }
        }

        // Ogólne: „najbliższy sklep”
        if (lower.contains("najblizszy sklep") || lower.contains("najbliższy sklep")
            || lower.contains("najblizszy market") || lower.contains("znajdz sklep"))
            && !lower.contains("restaur") {
            return ("sklep", "sklep")
        }
        return nil
    }

    /// „Gdzie jestem” / „jaki jest mój adres” — najczęstsze pytanie, wcześniej bez obsługi.
    private static func isWhereAmI(_ lower: String) -> Bool {
        let keys = [
            "gdzie jestem", "gdzie ja jestem", "gdzie teraz jestem",
            "jaki jest moj adres", "jaki jest mój adres", "moj adres", "mój adres",
            "podaj moj adres", "podaj mój adres", "powiedz moj adres",
            "jaka jest moja lokalizacja", "co to za miejsce", "co to za miejscowosc",
            "co to za miejscowość", "w jakim mieście jestem", "w jakim miescie jestem",
            "ktore miasto", "które miasto", "jaki powiat", "jaka gmina",
            "ktore województwo", "które województwo", "jaki jest kod pocztowy",
            "kod pocztowy", "jaki jest moj kod pocztowy", "podaj kod pocztowy",
            "ktory jestem kod", "ktory kod pocztowy",
            "gdzie sie znajduje", "gdzie się znajduje", "gdzie sie znajduj",
            "co sie znajduje", "co się znajduje", "co tu sie znajduje",
            "co tu znajduje", "powiedz mi gdzie sie", "powiedz gdzie sie",
            "jaki numer domu", "podaj numer domu", "na jakiej ulicy",
            "na jakiej ulicy jestem", "jaka ulica tu", "jaka ulica tu jest",
            "jaka jest ta ulica", "jak sie nazywa ta ulica", "jak nazywa sie ulica",
            "jak nazywa się ulica", "jak nazywa sie to miejsce", "jak nazywa się to miejsce",
            "jakie to miejsce", "co tutaj jest", "co tu jest", "tu jestem",
            "czym jest to miejsce", "where am i", "what is my address", "my location", "where i am"
        ]
        if keys.contains(where: { lower.contains($0) }) { return true }
        if lower.contains("co to za") {
            let tail = lower.replacingOccurrences(of: "co to za ", with: "")
            return tail.contains("ulic") || tail.contains("miejsc") || tail.contains("drog")
                || tail.contains("skrzyz") || tail.contains("skrzyż") || tail.contains("rondo")
                || tail.contains("osiedl") || tail.contains("dzielnic") || tail.contains("plac")
        }
        return false
    }

    private static func isStreetInfo(_ lower: String) -> Bool {
        let placeWord = lower.contains("ulic") || lower.contains("miejsc") || lower.contains("drog")
            || lower.contains("skrzyz") || lower.contains("skrzyż") || lower.contains("rondo")
            || lower.contains("osiedl") || lower.contains("dzielnic") || lower.contains("plac")
            || lower.contains("okolic") || lower.contains("kwartal") || lower.contains("kwartał")

        let infoWord = lower.contains("informac") || lower.contains("opowiedz") || lower.contains("powiedz")
            || lower.contains("opisz") || lower.contains("opis") || lower.contains("charakterystyk")
            || lower.contains("co wiesz") || lower.contains("wiesz o") || lower.contains("dane o")
            || lower.contains("teryt") || lower.contains("kod pocztowy") || lower.contains("przedluz")
            || lower.contains("co to za ulic") || lower.contains("powiedz o ulic") || lower.contains("opowiedz o ulic")
            || lower.contains("informacje o ulic") || lower.contains("info o ulic") || lower.contains("wiadomosci o ulic")

        if !placeWord { return false }
        if infoWord { return true }
        if isAboutCurrentPlace(lower) { return true }
        return lower.contains("o ") || lower.contains("obec") || lower.contains("tej")
            || lower.contains("tutaj") || lower.contains("tu ")
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

        // „pokaż mnie na mapie” / „wyśrodkuj” — akcja mapy, nie kafelek
        if isRecenterMap(lower) { return nil }

        // Pytania o stan rzeczy, nie o kafelek: „pokaż mi stan baku”,
        // „pokaż ile paliwa zostało”, „pokaż zasięg”.
        if hasFuelVocabulary(lower) && (
            lower.contains("bak") || lower.contains("ile") || lower.contains("poziom")
                || lower.contains("stan") || lower.contains("procent") || lower.contains("zasieg")
        ) { return nil }

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
        if lower.contains("korek") || lower.contains("korki") || lower.contains("utrudnien") {
            return true
        }
        if lower.contains("zakork") || lower.contains("stoi") || lower.contains("stoją") || lower.contains("stoja")
            || lower.contains("przeciez") || lower.contains("przecież") {
            return true
        }
        if lower.contains("ryzyko") || lower.contains("zagroz") { return true }
        if lower.contains("ruch") && (lower.contains("ulic") || lower.contains("drog") || lower.contains("doklad")) {
            return true
        }
        // „jak szybko dojadę”, „ile się stoi”, „czy utknę” — tylko poza paliwem.
        let travelTime = lower.contains("jak szybko") || lower.contains("ile sie stoi")
            || lower.contains("ile długo") || lower.contains("ile dlugo") || lower.contains("utkne")
            || lower.contains("zakorkuje") || lower.contains("korki")
        let aboutFuel = lower.contains("paliw") || lower.contains("litro") || lower.contains("litr")
            || lower.contains("zuzyc") || lower.contains("spalan")
        return travelTime && !aboutFuel
    }

    private static func isNavigation(_ lower: String) -> Bool {
        // Pytanie o paliwo / ulicę / korki NIE jest trasą, nawet jeśli zawiera
        // słowo „trasa”. Bez tego „czy starczy mi tego na trasę” i „ile paliwa
        // na trasie” zamieniały się w nawigację do „trasę”.
        if isNonNavigationQuestion(lower) { return false }

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
        if lower.hasPrefix("do ") || lower.hasPrefix("na ") {
            return true
        }
        if lower.contains(" na rondo") || lower.contains(" do rondo") { return true }
        return false
    }

    /// Pytania, które wyglądają jak nawigacja („na ile…”, „do…”), ale nią nie są.
    private static func isNonNavigationQuestion(_ lower: String) -> Bool {
        if isWhereAmI(lower) || isStreetInfo(lower) || isStreetHistory(lower) || isTraffic(lower) { return true }
        if isFuelLevel(lower) || isFuelRange(lower) || isFuelCost(lower) || isNearestFuel(lower) { return true }
        if isFoodRequest(lower) || isSpeedLimit(lower) { return true }
        if isRecenterMap(lower) || isCapabilitiesHelp(lower) { return true }
        if lower.hasPrefix("na ile") || lower.hasPrefix("do ktorego") || lower.hasPrefix("do jakiego") { return true }
        return false
    }

    /// Słowa UI / komend, które nigdy nie są celem nawigacji (np. „widok”, „mapę”).
    static func looksLikeUIOrCommandDestination(_ destination: String) -> Bool {
        let d = folded(destination)
        let blockedExact = [
            "widok", "widoku", "mape", "mapa", "mapy", "ekran", "ekranu",
            "kafelek", "kafelki", "panel", "przycisk", "kamera", "zoom",
            "asystent", "asystenta", "nasluch", "nasluchiwanie"
        ]
        if blockedExact.contains(d) { return true }
        let blockedParts = [
            "wysrodk", "centruj", "centrow", "recenter",
            "ukryj", "schowaj", "pokaz", "wlacz", "wylacz"
        ]
        return blockedParts.contains(where: { d.contains($0) })
    }

    private static func isBarePlaceName(_ cleaned: String, lower: String) -> Bool {
        let words = cleaned.split(separator: " ").map(String.init)
        guard words.count >= 1, words.count <= 6 else { return false }
        if isNoiseOrFiller(lower) { return false }
        let blocked = ["cześć", "czesc", "hej", "hello", "dzięki", "dzieki", "ok", "dobra", "pomóż", "pomoc"]
        if blocked.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) { return false }
        // Czasowniki w trybie rozkazującym — to prośba o akcję, której Drive Mate
        // nie umie, a nie nazwa miejsca. Bez tego „zadzwoń do mamy” / „wyślij smsa”
        // były interpretowane jako nawigacja do „mamy” / „smsa do tomka”.
        let unsupportedActions = [
            "zadzwon", "zadzwon", "wyslij", "wyślij", "zapisz", "zablokuj", "odblokuj",
            "kup", "zaplac", "zapłać", "zamow", "zamów", "zarezerwuj", "wydrukuj",
            "zadzwoń", "napisz", "odpowiedz", "otworz", "otwórz", "wylacz telefon",
            "zdejmij telefon", "zutrzymaj", "usun", "skasuj", "wystaw", "ustaw alarm",
            "sms", "telefon", "mail", "e-mail", "instagram", "facebook", "youtube"
        ]
        if unsupportedActions.contains(where: { lower.contains($0) }) { return false }
        // Komendy UI mapy — „wyśrodkuj mi widok” NIE jest miejscem o nazwie „widok”.
        let uiCommands = [
            "wysrodk", "centruj", "centrow", "recenter",
            "ukryj", "schowaj", "pokaz", "wlacz", "wylacz",
            "powiększ", "powieksz", "pomniejsz", "zoom"
        ]
        if uiCommands.contains(where: { lower.contains($0) }) { return false }
        if isRecenterMap(lower) || isCapabilitiesHelp(lower) { return false }
        if looksLikeUIOrCommandDestination(cleaned) { return false }
        let questionVerbs = ["jest", "mam", "gdzie", "ile", "jak", "czy", "co ", "kiedy", "dlaczego", "dlaczego", "wylosuj", "losuj"]
        if questionVerbs.contains(where: { lower.hasPrefix($0) }) { return false }
        if isNavigation(lower) || isTraffic(lower) || isStreetInfo(lower) || isFoodRequest(lower) { return false }

        // TYLKO gdy jest wyraźny hint miejsca — nigdy „yhm”, „coś”, losowe słowa.
        guard hasPlaceHint(lower) else { return false }
        if words.count == 1 { return cleaned.count >= 4 }
        let first = folded(words[0])
        let imperativeSuffixes = ["uj", "aj", "ij", "yj", "nij", "mij", "szy"]
        if first.count >= 4, imperativeSuffixes.contains(where: { first.hasSuffix($0) }) {
            return false
        }
        return true
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

    /// Wyciąga nazwę ulicy/miejsca z wypowiedzi o charakterze pytania.
    ///
    /// Stary kod brał „o ” jako ostatni wyraz kluczowy, przez co z „co to za ulica?”
    /// leciał ciąg „ulica?”. Teraz wytniamy wypełniacze i zostawiamy nazwę własną.
    private static func extractStreetQuery(_ text: String, kind: StreetQueryKind) -> String? {
        let keywords: [String]
        switch kind {
        case .history:
            keywords = [
                "historia ulicy", "historię ulicy", "historie ulicy", "historia ",
                "o historii ", "historię ", "opowiedz o ", "opowiedz historię ",
                "opowiedz o ", "ciekawostka o ", "ciekawostki o ", "ciekawostke o ",
                "powiedz o ", "o ", "na temat "
            ]
        case .traffic:
            keywords = [
                "korki na ulicy", "korek na ulicy", "korki na", "korek na",
                "ryzyko na", "utrudnienia na", "utrudnien na", "ruch na ulicy", "ruch na",
                "na ulicy", "ulicy", "dla", "na trasie", "na ", "w ", "wokół ", "wokół"
            ]
        case .info:
            keywords = [
                "informacja o ulicy", "informacje o ulicy", "info o ulicy",
                "powiedz o ulicy", "opowiedz o ulicy", "opisz ulice", "opisz ulicę",
                "o ulicy", "o ulicę", "ulicy", "ulicę", "na temat", "o ", "w ", "dla "
            ]
        }

        guard let raw = extractAfterKeywords(text, keywords: keywords) else { return nil }
        let cleaned = DriveIntentQueryHelpers.cleanStreetQuery(raw)
        return cleaned.isEmpty ? nil : cleaned
    }

    private enum StreetQueryKind {
        case info, history, traffic
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
            // „Powiedz coś o tej ulicy” — historyczne / ciekawe rzeczy, nie suchy adres.
            return await executeStreetInfoCard(query: query, historical: true, addressMode: false)

        case .tellTrivia:
            return DriveTriviaStore.nextSpokenFact()

        case .findNearestStore(let query, let label):
            guard let coordinate = MapKitNavigationService.shared.location?.coordinate else {
                return "Brak lokalizacji — nie mogę znaleźć \(label)."
            }
            let interrupting = MapKitNavigationService.shared.mapState?.isNavigating == true
            return await StoreOfferService.shared.findAndPresentNearest(
                brandQuery: query,
                brandLabel: label,
                near: coordinate,
                interruptingActiveRoute: interrupting
            )

        case .setCarModel(let model):
            return executeSetCarModel(model)

        case .navigateToPastVisit(let daysAgo):
            return await executePastVisit(daysAgo: daysAgo)

        case .setChromeTile(let query, let visible):
            return executeChromeVisibility(query: query, visible: visible)

        case .recenterMap:
            return executeRecenterMap()

        case .showCapabilities:
            return executeShowCapabilities()

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
            return await executeMusic(command)

        case .speedLimit:
            return await executeSpeedLimit()

        case .streetHistory(let query):
            return await executeStreetInfoCard(query: query, historical: true, addressMode: false)

        case .fuelCost:
            return await executeFuelCost()

        case .fuelLevel:
            return executeFuelLevel()

        case .fuelRange:
            return await executeFuelRange()

        case .nearestFuel(let preferCheapest):
            return await executeNearestFuel(preferCheapest: preferCheapest)

        case .whereAmI:
            return await executeStreetInfoCard(query: nil, historical: false, addressMode: true)

        case .answer(let hint):
            return hint

        case .unsupported(let hint):
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return DriveIntentParser.unknownCommandReply }
            // Model czasem dokleja katalog umiejętności — tnij do krótkiej odmowy.
            let lower = DriveIntentQueryHelpers.foldForMatching(trimmed)
            if lower.contains("umiem") || lower.contains("umie natomiast") || lower.contains("mogę zaprowad")
                || lower.contains("moge zaprowad") {
                return DriveIntentParser.unknownCommandReply
            }
            return trimmed

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

    private static func executeStreetInfoCard(
        query: String?,
        historical: Bool,
        addressMode: Bool = false
    ) async -> String {
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
                    if addressMode { return "Nie znalazłem miejsca „\(query)”." }
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
                if addressMode { return "Brak lokalizacji — nie mogę odczytać adresu." }
                return historical
                    ? "Nie wiem, o jakiej ulicy mówisz."
                    : "Brak lokalizacji do odczytu obecnej ulicy."
            }

            // „Gdzie jestem” — chcemy konkretnych danych, nie narracji.
            if addressMode {
                var parts = ["Jesteś przy: \(title)."]
                if !addressHint.isEmpty {
                    parts.append("Okolica: \(addressHint).")
                }
                if let coordinate,
                   let knowledge = await PolishStreetKnowledgeService.lookup(
                    coordinate: coordinate,
                    preferredName: title,
                    wantCuriosity: false
                   ) {
                    if let city = knowledge.city, !city.isEmpty { parts.append("Miejscowość: \(city).") }
                    if let house = knowledge.houseNumber, !house.isEmpty { parts.append("Numer: \(house).") }
                    if let postcode = knowledge.postcode, !postcode.isEmpty {
                        parts.append("Kod pocztowy: \(postcode).")
                    }
                    if let municipality = knowledge.municipality, !municipality.isEmpty {
                        parts.append("Gmina: \(municipality).")
                    }
                    if let kind = knowledge.streetKind, !kind.isEmpty { parts.append("Rodzaj: \(kind).") }
                    if let district = knowledge.osmContext, !district.isEmpty {
                        parts.append("Dzielnica: \(district).")
                    }
                }
                let reply = parts.joined(separator: " ")
                DriveInfoCardStore.shared.present(.street(title: title, body: reply, image: nil))
                if let coordinate {
                    Task { @MainActor in
                        let photo = await AppleMapsPlaceVisuals.placePhoto(at: coordinate)
                        DriveInfoCardStore.shared.updateStreetImage(photo)
                    }
                }
                return reply
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
                        Opowiedz 2–3 krótkie zdania o miejscu „\(place)”\(district) w Polsce.
                        Priorytet: historyczna ciekawostka, pochodzenie nazwy, znane wydarzenie albo charakter okolicy.
                        Brzmij jak przewodnik w aucie. BEZ kodów TERYT/SIMC, kodów pocztowych i żargonu rejestrów.
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

    private static func executeMusic(_ command: MusicPlaybackCommand) async -> String {
        let reply = await MusicSourceController.shared.applyVoiceCommand(command)
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

    private static func executeRecenterMap() -> String {
        guard let mapState = MapKitNavigationService.shared.mapState else {
            return "Nie mam aktywnej mapy do wyśrodkowania."
        }
        // Na MainActor — ten sam efekt co przycisk wyśrodkowania.
        mapState.recenterOnUser()
        // Powtórz w następnym ticku UI — gdy MapDriveView był w AR / nie dostał GPS.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            mapState.recenterOnUser()
        }
        if mapState.isNavigating {
            return "Wyśrodkowuję widok na Tobie."
        }
        return "Wyśrodkowuję mapę na Tobie."
    }

    static let capabilityItems: [String] = [
        "Nawigacja Apple Maps — trasa, start z GPS lub innego miejsca",
        "Auto-przeliczanie trasy po zjeździe z drogi",
        "Korki i utrudnienia w okolicy",
        "Info i ciekawostki o ulicy / miejscu",
        "Losowe ciekawostki na hasło „powiedz ciekawostkę”",
        "Paliwo: poziom baku, zasięg, koszt trasy, stacje",
        "Najbliższa restauracja, sklep (Żabka, Lewiatan…) i stacja paliw",
        "Muzyka: pauza, play, następny, poprzedni",
        "Wyśrodkowanie mapy, tryb AR i ukrywanie kafelków UI",
        "Przywrócenie przerwanej trasy"
    ]

    private static func executeShowCapabilities() -> String {
        // Krótka pauza, żeby TTS zdążył zacząć zanim okienko się pojawi.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            DriveInfoCardStore.shared.present(.capabilities(items: capabilityItems))
        }
        return "Pokazuję, co umiem — okienko zamknie się samo albo powiedz „Zamknij”."
    }

    /// Wspólne wejście dla wszystkich pytań o paliwo — ładne komunikaty zamiast odmowy.
private static let noCarHint = "Nie znam Twojego auta. Powiedz „moje auto to Toyota Corolla” albo wpisz model w Ustawieniach — wtedy policzę spalanie."
private static let noRouteHint = "Nie mam aktywnej trasy — powiedz gdzie lecimy, a oszacuję zużycie."

private static func executeFuelCost() async -> String {
    let profile = FuelProfile.shared
    guard profile.hasCar else { return noCarHint }
    guard let consumption = profile.consumptionLPer100, consumption > 0 else { return noCarHint }
    if profile.isElectric {
        return "To auto jest elektryczne — spalania w litrach nie liczę. Powiedz trasę, a sprawdzę dystans."
    }

    let mapState = MapKitNavigationService.shared.mapState
    let isNavigating = mapState?.isNavigating == true

    // Preferuj długość trasy MapKit; w trakcie jazdy — pozostały dystans.
    let km: Double
    if isNavigating, let remaining = currentRouteDistanceKm(), remaining > 0.05 {
        km = remaining
    } else if let route = mapState?.route, route.distance > 0 {
        km = route.distance / 1000
    } else if let destination = mapState?.destinationCoordinate,
              let origin = MapKitNavigationService.shared.location?.coordinate {
        let straight = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        km = (straight * 1.25) / 1000
    } else {
        return noRouteHint
    }

    let liters = km * (consumption / 100)
    let price = profile.pricePLNPerLiter
    let cost = liters * price
    let model = profile.carModel
    let modelLabel = model.isEmpty ? "Twojego auta" : model

    DriveInfoCardStore.shared.present(
        .fuelCost(
            distanceKm: km,
            liters: liters,
            costPLN: cost,
            carModel: model.isEmpty ? "Twoje auto" : model,
            consumptionLPer100: consumption
        )
    )

    // Jasno: km + litry + koszt (cena z profilu, spalanie z modelu).
    let distancePhrase = isNavigating
        ? String(format: "Do celu zostało %.1f km", km)
        : String(format: "Trasa ma %.1f km", km)
    return String(
        format: "%@. Zużyjesz około %.1f l paliwa (%.1f l/100 km, %@). Koszt to około %.0f zł przy %.2f zł za litr.",
        distancePhrase, liters, consumption, modelLabel, cost, price
    )
}

/// Stan baku — ile litrów, jaki procent, zasięg.
private static func executeFuelLevel() -> String {
    let profile = FuelProfile.shared
    guard profile.hasCar else { return noCarHint }
    if profile.isElectric {
        return "To auto jest elektryczne — zasięg liczę w kilometrach, nie na litrach. Powiedz trasę, a sprawdzę, czy zdążysz."
    }

    let liters = profile.litersInTank()
    let percent = profile.levelPercent
    let range = profile.rangeKm() ?? 0
    let price = profile.pricePLNPerLiter

    DriveInfoCardStore.shared.present(
        .fuelGauge(
            levelPercent: percent,
            liters: liters,
            tankCapacity: profile.tankCapacityLiters,
            rangeKm: range,
            carModel: profile.carModel.isEmpty ? "Twoje auto" : profile.carModel,
            costToFillPLN: (profile.tankCapacityLiters - liters) * price
        )
    )

    var reply = String(
        format: "W baku masz około %.1f l, czyli %.0f procent. To starczy na jakieś %.0f km.",
        liters, percent * 100, range
    )
    if profile.isBelowReserve {
        reply += " Paliwo jest poniżej rezerwy — warto zatankować."
    }
    if let destination = MapKitNavigationService.shared.mapState?.destinationTitle,
       let remaining = currentRouteDistanceKm(),
       let check = profile.sufficiency(distanceKm: remaining) {
        reply += check.fits
            ? " Do \(destination) dojedziesz bez tankowania."
            : " Do \(destination) zabraknie około \(String(format: "%.1f", max(0, check.neededLiters - liters))) l."
    }
    return reply
}

/// Zasięg — na ile wystarczy i czy dowiezie do celu.
private static func executeFuelRange() async -> String {
    let profile = FuelProfile.shared
    guard profile.hasCar else { return noCarHint }
    guard let consumption = profile.consumptionLPer100, consumption > 0 else { return noCarHint }
    if profile.isElectric {
        return "Auto elektryczne — spalania nie liczę na litrach. Na ile kilometrów wystarczy, policzę po trasie."
    }

    let range = profile.rangeKm(consumption: consumption) ?? 0
    var reply = String(
        format: "Na obecne paliwo przejedziesz około %.0f km. W baku jest %.0f procent baku.",
        range, profile.levelPercent * 100
    )

    // Czy cel z aktualnej trasy jest w zasięgu.
    if let distanceKm = currentRouteDistanceKm() {
        if let check = profile.sufficiency(distanceKm: distanceKm, consumption: consumption) {
            let destination = MapKitNavigationService.shared.mapState?.destinationTitle ?? "celu"
            if check.fits {
                let margin = range - distanceKm
                reply += String(
                    format: " Do %@ dojedziesz spokojnie — zostanie około %.0f km zasięgu.",
                    destination, max(0, margin)
                )
            } else {
                let deficitLiters = check.neededLiters - profile.litersInTank()
                let extraKm = max(0, range - distanceKm)
                reply += String(
                    format: " Do %@ zabraknie — brakuje około %.1f l, czyli %.0f km. Trzeba zatankować albo szukać stacji po drodze.",
                    destination, max(0, deficitLiters), extraKm
                )
                if let coordinate = MapKitNavigationService.shared.location?.coordinate {
                    let stationReply = await GasStationOfferService.shared.findAndPresent(
                        near: coordinate,
                        preferCheapest: false,
                        interruptingActiveRoute: MapKitNavigationService.shared.mapState?.isNavigating == true
                    )
                    reply += " \(stationReply)"
                }
            }
        }
    } else {
        reply += " Nie mam jeszcze wyznaczonej trasy, żeby porównać z celem."
    }

    DriveInfoCardStore.shared.present(
        .fuelGauge(
            levelPercent: profile.levelPercent,
            liters: profile.litersInTank(),
            tankCapacity: profile.tankCapacityLiters,
            rangeKm: range,
            carModel: profile.carModel.isEmpty ? "Twoje auto" : profile.carModel,
            costToFillPLN: (profile.tankCapacityLiters - profile.litersInTank()) * profile.pricePLNPerLiter
        )
    )
    return reply
}

/// Pozostały dystans do celu z aktywnej trasy (km) — nil gdy brak trasy.
private static func currentRouteDistanceKm() -> Double? {
    guard let mapState = MapKitNavigationService.shared.mapState,
          mapState.isNavigating else { return nil }

    if let remaining = RouteGeometry.remainingDistanceMeters(
        along: mapState.route?.polyline,
        from: MapKitNavigationService.shared.location?.coordinate
    ), remaining > 0 {
        return remaining / 1000
    }

    guard let destination = mapState.destinationCoordinate else { return nil }
    var origin = MapKitNavigationService.shared.location?.coordinate
    if origin == nil, let polyline = mapState.route?.polyline {
        origin = RouteGeometry.coordinate(along: polyline, progress: 0)
    }
    guard let origin else {
        if let route = mapState.route { return route.distance / 1000 }
        return nil
    }

    let straight = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    return (straight * 1.25) / 1000
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
        let lower = DriveIntentQueryHelpers.foldForMatching(text)
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
