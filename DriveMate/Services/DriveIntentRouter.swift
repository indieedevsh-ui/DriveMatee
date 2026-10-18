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
    /// Ile czasu zostało do końca aktywnej trasy.
    case remainingTravelTime
    /// Zadaj łamigówkę (opcjonalnie kategoria: math/fantasy/science/philosophy).
    case posePuzzle(categoryRaw: String?)
    /// Powtórz ostatnią łamigówkę (głos + kafelek).
    case repeatPuzzle
    case cancelListening
    case cancelRoute
    /// Przywróć trasę przerwaną przez zjazd (restauracja / stacja / nowa nawigacja).
    case restoreInterruptedRoute
    case music(MusicPlaybackCommand)
    case speedLimit
    /// Kiedy / gdzie skręcić (następny manewr, rondo, skrzyżowanie).
    case nextTurnInfo
    /// Przelicz trasę pod inny manewr na następnym skrzyżowaniu (prosto / lewo / prawo).
    case preferManeuver(direction: TurnDirection)
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
    /// Przezroczystość liquid glass kafelków (`true` = 35% regular, `false` = 90% regular).
    case setTilesTransparency(moreTransparent: Bool)
    /// Przeczytaj na głos aktualnie widoczny kafelek / ofertę.
    case readVisibleTile
    /// Wyśrodkuj mapę / widok na lokalizacji kierowcy.
    case recenterMap
    /// Włącz / wyłącz ciągłe nagrywanie.
    case setRecording(enabled: Bool)
    /// Ustaw lub zmień głośność aplikacji (0…1, albo delta).
    case setVolume(level: Double?, delta: Double?)
    /// Przełącz tryb jazdy (samochód / rower).
    case setTravelMode(TravelMode)
    /// Włącz / wyłącz tryb AR (samochód) albo kompas (rower).
    case setOverlayMode(ar: Bool?, compass: Bool?)
    /// Pokaż okienko z listą umiejętności Drive Mate.
    case showCapabilities
    /// Zapisz / zaktualizuj dom, pracę lub własne miejsce (`query == nil` → bieżąca lokalizacja).
    case savePlace(slot: SavedPlaceSlot, customLabel: String?, replaceExisting: Bool, query: String?)
    /// Pokaż okienko z wpisaniem nazwy (np. po „zapamiętaj moją szkołę”).
    case promptSavePlaceName(label: String)
    /// Pobierz mapy offline — okienko z obszarem (domyślnie 10 km).
    case downloadOfflineMaps
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

        // Nagrywanie / głośność / tryb jazdy / AR·kompas — przed chrome i recenter
        if let recording = extractRecordingCommand(from: lower) {
            return .setRecording(enabled: recording)
        }
        if let volume = extractVolumeCommand(from: lower) {
            return .setVolume(level: volume.level, delta: volume.delta)
        }
        if let mode = extractTravelModeCommand(from: lower) {
            return .setTravelMode(mode)
        }
        if let overlay = extractOverlayModeCommand(from: lower) {
            return .setOverlayMode(ar: overlay.ar, compass: overlay.compass)
        }

        // Wyśrodkuj widok mapy PRZED chrome — „pokaż mnie na mapie” / „wyśrodkuj” ≠ ukryj/pokaż kafelek
        if isRecenterMap(lower) {
            return .recenterMap
        }

        // „Przeczytaj mi to” — odczyt widocznego kafelka
        if isReadVisibleTile(lower) {
            return .readVisibleTile
        }

        // Przezroczystość kafelków (przed chrome — „kafelki” + przezroczystość)
        if let moreTransparent = extractTilesTransparency(from: lower) {
            return .setTilesTransparency(moreTransparent: moreTransparent)
        }

        // Ukryj / pokaż kafelki UI
        if let chrome = extractChromeVisibility(from: lower) {
            return .setChromeTile(tileQuery: chrome.query, visible: chrome.visible)
        }

        // Mapy offline — przed nawigacją („pobierz mapę” ≠ cel trasy)
        if isOfflineMapDownload(lower) {
            return .downloadOfflineMaps
        }

        // „Co potrafisz?” → okienko umiejętności
        if isCapabilitiesHelp(lower) {
            return .showCapabilities
        }

        // Dom / praca / własne miejsca — przed nawigacją i „gdzie jestem”
        if let save = extractSavePlaceCommand(from: cleaned, lower: lower) {
            return save
        }

        // „Gdzie jestem” / „jaki jest mój adres” — najczęstsze pytanie, wyprzedza info o ulicy
        if isWhereAmI(lower) {
            return .whereAmI
        }

        // Ogólna ciekawostka (przed historią ulicy — „powiedz ciekawostkę” ≠ ulica)
        if isTriviaRequest(lower) {
            return .tellTrivia
        }

        // Powtórz zagadkę (przed nową łamigówką)
        if isRepeatPuzzle(lower) {
            return .repeatPuzzle
        }

        // Łamigówki / zagadki (przed streetInfo — „opowiedz zagadkę” ≠ ulica)
        if isPosePuzzle(lower) {
            let cat = DrivePuzzleService.category(fromFolded: lower)
            return .posePuzzle(categoryRaw: cat?.rawValue)
        }

        // ETA — ile czasu do końca trasy (przed paliwem / nawigacją)
        if isRemainingTravelTime(lower) {
            return .remainingTravelTime
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
            // „czy gdzieś mogę się spodziewać korków” → analiza trasy, bez szukania POI.
            if isAboutCurrentPlace(lower) || isGeneralRouteTrafficQuestion(lower) {
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

        // „Chcę jechać prosto / w lewo na następnym” — zmiana trasy (przed pytaniem o manewr)
        if let prefer = extractPreferManeuver(lower) {
            return .preferManeuver(direction: prefer)
        }

        // Kiedy / gdzie skręcić
        if isNextTurnInfo(lower) { return .nextTurnInfo }

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
            "hej", "hey", "cześć", "czesc", "siema", "elo",
            // Resztki po „Hey Drive …” z ASR
            "mate", "drive", "drajw", "draj", "dryve", "draif", "draiw",
            "drivemate", "drajwmejt", "drive mate", "drajw mate"
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
        if isFoodRequest(lower) || isSpeedLimit(lower) || isNextTurnInfo(lower) || isWhereAmI(lower) { return true }
        if extractPreferManeuver(lower) != nil { return true }
        if isOfflineMapDownload(lower) { return true }
        if extractSavePlaceCommand(from: lower, lower: lower) != nil { return true }
        if isTriviaRequest(lower) || extractStoreSearch(from: lower) != nil { return true }
        if isRemainingTravelTime(lower) || isPosePuzzle(lower) { return true }
        if isRecenterMap(lower) || isCapabilitiesHelp(lower) { return true }
        if extractMusicCommand(from: lower) != nil { return true }
        if isCancelRoute(lower) || isCancelListening(lower) || isRestoreInterruptedRoute(lower) { return true }
        let domainKeys = [
            "paliw", "trase", "trasa", "nawig", "kork", "ulic", "adres", "restaur",
            "stacj", "tankow", "muzyk", "utwor", "piosenk", "wysrodk", "centruj",
            "potrafisz", "umiesz", "gdzie jestem", "ile mam", "dowiez",
            "lamigow", "zagadk", "ile jeszcze", "ile czasu", "eta"
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
            "wysrodkuj", "wysrodkowac", "wysrodkowanie", "wysrodkoj", "wysrodku",
            "zesrodkuj", "zesrodkowac", "srodkuj", "srodkowanie",
            "wycentruj", "wycentrowac", "centruj", "centrowanie", "wycentrowanie",
            "recenter", "center map", "centre map", "center on me", "center view",
            "pokaz mnie na mapie", "gdzie jestem na mapie",
            "wysrodkuj widok", "wycentruj widok", "centruj widok",
            "wysrodkuj mape", "wycentruj mape", "centruj mape",
            "wysrodkuj kamere", "wroc do mnie na mapie",
            "wycentruj na mnie", "wysrodkuj na mnie", "centruj na mnie",
            "na moja lokalizacje", "na mojej lokalizacji", "kamera na mnie",
            "wroc na mnie", "wroc do mnie", "follow me", "moja pozycja na mapie"
        ]
        guard phrases.contains(where: { lower.contains($0) })
                || (lower.contains("pokaz mnie") && (lower.contains("map") || lower.contains("widok")))
                || (lower.contains("srodk") && (lower.contains("widok") || lower.contains("map")
                    || lower.contains("mnie") || lower.contains("kamer")))
        else { return false }

        // Ukryj/pokaż kafelek „wyśrodkuj” — nie recenter
        if (lower.contains("kafelek") || lower.contains("przycisk"))
            && (lower.contains("ukryj") || lower.contains("schowaj")
                || lower.contains("wylacz") || lower.contains("wlacz")
                || lower.contains("pokaz") || lower.contains("przywroc")) {
            return false
        }
        // Samo „ukryj wyśrodkuj” / „schowaj wyśrodkuj” bez „widok/mapę”
        if (lower.contains("ukryj") || lower.contains("schowaj") || lower.contains("wylacz"))
            && (lower.contains("wysrodk") || lower.contains("centru"))
            && !lower.contains("widok") && !lower.contains("map") && !lower.contains("mnie")
            && !lower.contains("kamer") {
            return false
        }
        return true
    }

    private static func extractRecordingCommand(from lower: String) -> Bool? {
        let mentionsRec =
            lower.contains("nagryw") || lower.contains("nagranie") || lower.contains("recording")
            || lower.contains("rekorder") || lower.contains("recorder")
            || (lower.contains("kamer") && (lower.contains("wlacz") || lower.contains("wylacz")
                || lower.contains("start") || lower.contains("stop")))
        guard mentionsRec else { return nil }
        // Chrome: „ukryj kafelek nagrywania”
        if lower.contains("kafelek") || lower.contains("przycisk") || lower.contains("wskaznik") {
            return nil
        }
        if lower.contains("wylacz") || lower.contains("zatrzymaj") || lower.contains("stop")
            || lower.contains("zakoncz nagr") || lower.contains("zakończ nagr")
            || lower.contains("koniec nagr") {
            return false
        }
        if lower.contains("wlacz") || lower.contains("start") || lower.contains("rozpoczn")
            || lower.contains("nagrywaj") || lower.contains("zacznij nagr") {
            return true
        }
        return nil
    }

    /// `level` absolutne 0…1 albo `delta` względne.
    private static func extractVolumeCommand(from lower: String) -> (level: Double?, delta: Double?)? {
        let mentionsVol =
            lower.contains("glosn") || lower.contains("volume") || lower.contains("ciszej")
            || lower.contains("glosniej") || lower.contains("scisz") || lower.contains("ścisz")
            || lower.contains("poglosnij") || lower.contains("podglosnij")
        // Samo „głośność” / „ścisz aplikację”
        guard mentionsVol
                || ((lower.contains("scisz") || lower.contains("poglosn") || lower.contains("podglosn"))
                    && (lower.contains("applik") || lower.contains("aplik") || lower.contains("drive")
                        || lower.contains("muzyk") || lower.contains("dzwiek") || lower.contains("dzwięk")))
        else { return nil }

        // Nie mylić z przezroczystością kafelków
        if lower.contains("przezroczyst") || lower.contains("transparent") { return nil }
        // „wycisz muzykę” = pauza, nie głośność 0 — zostaw music handlerowi jeśli tylko pauza
        if (lower.contains("wycisz muzyk") || lower.contains("wycisz piosen"))
            && !lower.contains("glosn") {
            return nil
        }

        // Absolutnie: „na 50”, „50%”, „do połowy”
        if lower.contains("polowa") || lower.contains("polowę") || lower.contains("polowe")
            || lower.contains("w polowie") {
            return (0.5, nil)
        }
        if lower.contains("maks") || lower.contains("max") || lower.contains("pelna")
            || lower.contains("pełna") || lower.contains("na full") {
            return (1.0, nil)
        }
        if lower.contains("minimum") || lower.contains("najciszej") || lower.contains("na zero") {
            return (0.05, nil)
        }
        if let pct = firstPercent(in: lower) {
            return (min(1, max(0, pct / 100)), nil)
        }
        // „głośność 7” / „na 7” (skala 0–10)
        if let n = firstNumber(in: lower), n <= 10, lower.contains("glosn") || lower.contains("volume") {
            return (min(1, max(0, n / 10)), nil)
        }

        if lower.contains("glosniej") || lower.contains("zwieksz glosn") || lower.contains("zwiększ glosn")
            || lower.contains("podglosnij") || lower.contains("poglosnij")
            || lower.contains("volume up") || lower.contains("louder") {
            return (nil, 0.12)
        }
        if lower.contains("ciszej") || lower.contains("zmniejsz glosn") || lower.contains("scisz")
            || lower.contains("ścisz") || lower.contains("volume down") || lower.contains("quieter") {
            return (nil, -0.12)
        }
        return nil
    }

    private static func extractTravelModeCommand(from lower: String) -> TravelMode? {
        let wantsBike =
            lower.contains("tryb rower") || lower.contains("rowerowy")
            || (lower.contains("rower") && (lower.contains("tryb") || lower.contains("wlacz")
                || lower.contains("przelacz") || lower.contains("przełącz") || lower.contains("zmien")
                || lower.contains("ustaw")))
            || lower.contains("bike mode") || lower.contains("bicycle mode")
        let wantsCar =
            lower.contains("tryb samochod") || lower.contains("samochodowy")
            || (lower.contains("samochod") && (lower.contains("tryb") || lower.contains("wlacz")
                || lower.contains("przelacz") || lower.contains("przełącz") || lower.contains("zmien")
                || lower.contains("ustaw")))
            || lower.contains("car mode") || lower.contains("auto mode")

        if wantsBike && !wantsCar { return .bike }
        if wantsCar && !wantsBike { return .car }
        return nil
    }

    /// `ar` / `compass` — true=włącz, false=wyłącz; dokładnie jedno ustawione.
    private static func extractOverlayModeCommand(from lower: String) -> (ar: Bool?, compass: Bool?)? {
        let mentionsAR =
            lower.contains(" tryb ar") || lower.contains("tryb ar") || lower.hasPrefix("ar ")
            || lower.contains(" ar ") || lower.hasSuffix(" ar") || lower == "ar"
            || lower.contains("augmented") || lower.contains("rzeczywistosc rozszerz")
            || lower.contains("rzeczywistość rozszerz") || lower.contains("kamera nawig")
            || lower.contains("nawigacj") && lower.contains("kamer")
        let mentionsCompass =
            lower.contains("kompas") || lower.contains("compass")

        guard mentionsAR || mentionsCompass else { return nil }
        // Nie mylić z „wyśrodkuj kompasem” etc.
        if lower.contains("wysrodk") || lower.contains("centruj") { return nil }

        let turnOff = lower.contains("wylacz") || lower.contains("zakoncz") || lower.contains("zakończ")
            || lower.contains("wylaczyc") || lower.contains("schowaj") || lower.contains("wylacz")
            || lower.contains("exit") || lower.contains("leave") || lower.contains("wroc do mapy")
            || lower.contains("wróć do mapy") || lower.contains("mapa z powrotem")
        let turnOn = lower.contains("wlacz") || lower.contains("wlaczyc") || lower.contains("uruchom")
            || lower.contains("otworz") || lower.contains("otwórz") || lower.contains("wejdz w")
            || lower.contains("wejdź w") || lower.contains("start")

        if mentionsCompass && !mentionsAR {
            if turnOff { return (nil, false) }
            if turnOn || lower.contains("tryb kompas") { return (nil, true) }
            return nil
        }
        if mentionsAR {
            if turnOff { return (false, nil) }
            if turnOn || lower.contains("tryb ar") { return (true, nil) }
            return nil
        }
        return nil
    }

    private static func firstPercent(in lower: String) -> Double? {
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,3})\s*%"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(match.range(at: 1), in: lower),
           let n = Double(lower[r]) {
            return n
        }
        if let regex = try? NSRegularExpression(pattern: #"(?:na|do|glosnosc|volume)\s*(\d{1,3})\b"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(match.range(at: 1), in: lower),
           let n = Double(lower[r]), n <= 100 {
            return n
        }
        return nil
    }

    private static func firstNumber(in lower: String) -> Double? {
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,3})\b"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(match.range(at: 1), in: lower) {
            return Double(lower[r])
        }
        return nil
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

    private static func isOfflineMapDownload(_ lower: String) -> Bool {
        let wantsMap = lower.contains("mape offline") || lower.contains("mapy offline")
            || lower.contains("offline map") || lower.contains("mape do offline")
            || lower.contains("mapy do offline") || lower.contains("offline mape")
            || (lower.contains("offline") && lower.contains("map"))
        let wantsDownload = lower.contains("pobierz") || lower.contains("sciagnij") || lower.contains("ściągnij")
            || lower.contains("pobieranie") || lower.contains("zapisz map") || lower.contains("sciagn")
            || lower.contains("download")
        if wantsMap && wantsDownload { return true }
        if lower.contains("pobierz mape") || lower.contains("pobierz mapy") { return true }
        if lower.contains("mapy offline") || lower.contains("mape offline") { return true }
        return false
    }

    private static func extractMusicCommand(from lower: String) -> MusicPlaybackCommand? {
        let musicContext = lower.contains("muzyk") || lower.contains("utwór") || lower.contains("utwor")
            || lower.contains("piosenk") || lower.contains("track") || lower.contains("playlist")
            || lower.contains("odtwarzacz") || lower.contains("song") || lower.contains("audio")

        let navConflict = lower.contains("zjazd") || lower.contains("skrzyż") || lower.contains("skrzyz")
            || lower.contains("ulic") || lower.contains("tras") || lower.contains("nawig")
            || lower.contains("kilometr") || lower.contains(" metr")
            || lower.contains("skret") || lower.contains("manewr")

        // Następny / poprzedni / przewiń / cofnij
        let wantsPrevious = lower.contains("poprzedni") || lower.contains("wcześniejsz") || lower.contains("wczesniejsz")
            || lower.contains("cofnij") || lower.contains("previous") || lower.contains("last track")
            || lower.contains("cofnij utwor") || lower.contains("cofnij utwór")
            || lower.contains("cofni") || lower.contains("wroc utwor") || lower.contains("wroc piosen")
        // `lower` jest już folded, więc „następny” → „nastepny”.
        let wantsNext = lower.contains("nastepn") || lower.contains("kolejn") || lower.contains("skip")
            || lower.contains("next") || lower == "dalej" || lower.hasPrefix("dalej ")
            || lower.contains("przesuń") || lower.contains("przesun") || lower.contains("przewin")
            || lower.contains("przewiń")

        if wantsPrevious {
            if musicContext { return .previous }
            if !navConflict, lower == "poprzedni" || lower.hasPrefix("poprzedni ")
                || lower == "cofnij" || lower.hasPrefix("cofnij ")
                || lower.contains("cofnij utwor") || lower.contains("poprzedni utwor") {
                return .previous
            }
        }
        if wantsNext {
            if musicContext || lower.contains("skip") || lower.contains("przewin") { return .next }
            if !navConflict, lower == "następny" || lower == "nastepny" || lower == "kolejny"
                || lower.hasPrefix("następn") || lower.hasPrefix("nastepn") || lower.hasPrefix("kolejn")
                || lower.contains("nastepny utwor") || lower.contains("przewin") {
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
            || lower.contains("wylacz muzyk") || lower.contains("wyłącz muzyk")
            || lower == "stop" || lower == "pause"
            || (musicContext && (lower.contains("zatrzymaj") || lower.contains("zatrzym") || lower.contains("stop") || lower.contains("wstrzymaj") || lower.contains("pauz"))) {
            return .pause
        }

        if lower == "pauza" || lower == "pause" { return .pause }
        if lower == "odpauzuj" || lower == "play" { return .resume }
        if (lower.contains("toggle") || lower.contains("przełącz") || lower.contains("przelacz")) && musicContext {
            return .toggle
        }

        return nil
    }

    /// Jednolite reguły miejsc:
    /// - „tutaj jest mój/moja Y” → bieżąca lokalizacja GPS
    /// - „zapamiętaj mój/moja Y” → okienko z wpisaniem nazwy/adresu
    /// - „… Y to X” / „zmień Y na X” → zapis z wyszukaniem X
    private static func extractSavePlaceCommand(from cleaned: String, lower: String) -> DriveIntent? {
        let isHere =
            lower.contains("tutaj jest") || lower.contains("tu jest")
            || lower.contains("to jest moj") || lower.contains("to jest moja") || lower.contains("to jest moje")
            || lower.contains("here is my") || lower.contains("this is my")
        let isRemember =
            lower.contains("zapamietaj") || lower.contains("zapamiętaj")
            || lower.contains("zapisz jako") || lower.contains("zapisz to jako")
            || lower.contains("oznacz jako")
            || (lower.contains("zapisz") && !lower.contains("zapisz trase") && !lower.contains("zapisz trasa"))
        let isChange =
            lower.contains("zmien") || lower.contains("zaktualizuj") || lower.contains("popraw")
            || lower.contains("przenies") || lower.contains("update ")

        guard isHere || isRemember || isChange || looksLikeAliasPlaceDefinition(lower) else { return nil }

        // „moja szkoła to UKEN” / „zapamiętaj dom to ul. Floriańska”
        if let alias = extractAliasPlaceDefinition(from: cleaned, lower: lower) {
            return savePlaceIntent(forLabel: alias.label, query: alias.query, replaceExisting: true)
        }

        // „zmień szkołę na UKEN” / „zmień dom na …”
        if isChange, let label = extractPlaceRoleLabel(from: lower) {
            let query = extractSavePlaceTargetQuery(from: cleaned, lower: lower, slotWord: label)
            if let query, !query.isEmpty {
                return savePlaceIntent(forLabel: label, query: query, replaceExisting: true)
            }
            // „zmień mój dom” bez adresu → okienko
            return .promptSavePlaceName(label: label)
        }

        guard let label = extractPlaceRoleLabel(from: lower) else { return nil }

        // „tutaj jest moja szkoła / mój dom / moja praca”
        if isHere {
            return savePlaceIntent(forLabel: label, query: nil, replaceExisting: true)
        }

        // „zapamiętaj mój dom / moją szkołę / moją pracę” → okienko
        if isRemember {
            return .promptSavePlaceName(label: label)
        }

        // Własna nazwa: „jako X”
        if let custom = extractCustomPlaceLabel(from: cleaned, lower: lower) {
            let query = extractSavePlaceTargetQuery(from: cleaned, lower: lower, slotWord: custom)
            if query == nil, isRemember || isChange {
                return .promptSavePlaceName(label: custom)
            }
            return savePlaceIntent(forLabel: custom, query: query, replaceExisting: true)
        }
        return nil
    }

    private static func savePlaceIntent(
        forLabel rawLabel: String,
        query: String?,
        replaceExisting: Bool
    ) -> DriveIntent {
        let label = SavedPlacesStore.canonicalLabel(for: rawLabel)
        let key = SavedPlacesStore.normalizeAliasKey(folded(label))
        switch key {
        case "dom", "home", "house":
            return .savePlace(slot: .home, customLabel: nil, replaceExisting: replaceExisting, query: query)
        case "praca", "work", "office":
            return .savePlace(slot: .work, customLabel: nil, replaceExisting: replaceExisting, query: query)
        default:
            return .savePlace(
                slot: .custom,
                customLabel: label,
                replaceExisting: replaceExisting,
                query: query
            )
        }
    }

    /// Wyciąga Y z „mój/moja Y” (dom, praca, szkoła, siłownia, …).
    private static func extractPlaceRoleLabel(from lower: String) -> String? {
        var rest = lower
        let stripChunks = [
            "zapamietaj ze ", "zapamiętaj że ", "zapamietaj ", "zapamiętaj ",
            "zapisz ze ", "zapisz że ", "zapisz jako ", "zapisz to jako ", "zapisz ",
            "oznacz jako ", "tutaj jest ", "tu jest ", "to jest ",
            "zmien ", "zaktualizuj ", "popraw ", "przenies ",
            "here is my ", "this is my ", "save as ", "remember my ", "remember "
        ]
        for chunk in stripChunks {
            if let r = rest.range(of: chunk) {
                rest = String(rest[r.upperBound...])
            }
        }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for poss in ["moja ", "moj ", "moje ", "mojej ", "mojego ", "moim ", "nasza ", "nasz ", "my "] {
            if rest.hasPrefix(poss) {
                rest = String(rest.dropFirst(poss.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Odetnij „na …” / „to …” jeśli zostały
        if let na = rest.range(of: " na ") {
            rest = String(rest[..<na.lowerBound])
        }
        if let to = rest.range(of: " to ") {
            rest = String(rest[..<to.lowerBound])
        }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard rest.count >= 2 else { return nil }

        let known: [(needle: String, label: String)] = [
            ("szkol", "Szkoła"), ("school", "Szkoła"),
            ("silown", "Siłownia"), ("gym", "Siłownia"), ("fitness", "Siłownia"),
            ("uczel", "Uczelnia"), ("uniwersyt", "Uniwersytet"), ("akadem", "Akademia"),
            ("przedszkol", "Przedszkole"),
            ("biuro", "Biuro"), ("garaz", "Garaż"),
            ("dom", "Dom"), ("home", "Dom"), ("house", "Dom"),
            ("prac", "Praca"), ("work", "Praca"), ("office", "Praca")
        ]
        for item in known where rest.contains(item.needle) || rest == item.needle {
            return item.label
        }
        // Dowolne inne Y (np. „kawa”, „siłownia X”) — max 3 słowa
        let words = rest.split(separator: " ").prefix(3).map(String.init)
        let joined = words.joined(separator: " ")
        guard joined.count >= 2, !isNoiseOrFiller(joined) else { return nil }
        return SavedPlacesStore.canonicalLabel(for: joined)
    }

    /// „moja szkoła to …” / „szkoła to …” — definicja aliasu, nie luźne „to”.
    private static func looksLikeAliasPlaceDefinition(_ lower: String) -> Bool {
        guard lower.contains(" to ") else { return false }
        let keys = [
            "szkol", "silown", "uczel", "uniwersyt", "akadem", "przedszkol",
            "biuro", "garaz", "fitness", "gym", "school",
            "dom", "home", "prac", "work", "office"
        ]
        return keys.contains(where: { lower.contains($0) })
            || lower.contains("moja ") || lower.contains("moj ") || lower.contains("moje ")
    }

    /// „(zapamiętaj) moja szkoła to UKEN” → label=Szkoła, query=UKEN.
    private static func extractAliasPlaceDefinition(
        from cleaned: String,
        lower: String
    ) -> (label: String, labelFold: String, query: String)? {
        var restFold = lower
        let stripPrefixes = [
            "zapamietaj ze ", "zapamiętaj że ", "zapamietaj ", "zapamiętaj ",
            "zapisz ze ", "zapisz że ", "zapisz ",
            "pamietaj ze ", "pamiętaj że ", "pamietaj ", "pamiętaj "
        ]
        for prefix in stripPrefixes {
            if restFold.hasPrefix(prefix) {
                restFold = String(restFold.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Zmapuj z powrotem na oryginał (dla wielkości liter w query, np. UKEN).
        let dropCount = lower.count - restFold.count
        let restCleaned: String = {
            guard dropCount > 0, dropCount <= cleaned.count else { return cleaned }
            let idx = cleaned.index(cleaned.startIndex, offsetBy: dropCount)
            return String(cleaned[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        // „moja szkoła to UKEN” / „szkoła to UKEN”
        if let toRange = restFold.range(of: " to ") {
            var labelPart = String(restFold[..<toRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for poss in ["moja ", "moj ", "moje ", "mojej ", "mojego ", "nasza ", "nasz "] {
                if labelPart.hasPrefix(poss) {
                    labelPart = String(labelPart.dropFirst(poss.count))
                    break
                }
            }
            let queryFold = String(restFold[toRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard labelPart.count >= 2, queryFold.count >= 2 else { return nil }
            // Query z oryginalnej wielkości liter
            let queryOriginal: String = {
                if let r = restCleaned.range(of: " to ", options: .caseInsensitive) {
                    return String(restCleaned[r.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                }
                return queryFold
            }()
            let label = SavedPlacesStore.canonicalLabel(for: labelPart)
            return (label, folded(label), queryOriginal)
        }

        // „zapamiętaj szkołę UKEN” / „zapamiętaj siłownię CityFit”
        if let r = restFold.range(
            of: #"^(szkol[aeyę]|silowni[aeę]|uczelni[aeę]|uniwersytet|akademi[aeę]|przedszkol[ea]|biuro|gara[zż])\s+(.+)$"#,
            options: .regularExpression
        ) {
            let matched = String(restFold[r])
            let parts = matched.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return nil }
            let label = SavedPlacesStore.canonicalLabel(for: String(parts[0]))
            let query = String(parts[1])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard query.count >= 2 else { return nil }
            return (label, folded(label), query)
        }

        return nil
    }

    private static func extractCustomPlaceLabel(from cleaned: String, lower: String) -> String? {
        let markers = ["jako ", "miejsce o nazwie ", "miejsce "]
        for marker in markers {
            guard let r = lower.range(of: marker) else { continue }
            let idx = cleaned.index(
                cleaned.startIndex,
                offsetBy: lower.distance(from: lower.startIndex, to: r.upperBound),
                limitedBy: cleaned.endIndex
            ) ?? cleaned.endIndex
            var label = String(cleaned[idx...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            // „zmień X na adres” — etykieta to X przed „ na ”
            if let na = folded(label).range(of: " na ") {
                let cut = label.index(label.startIndex, offsetBy: folded(label).distance(from: folded(label).startIndex, to: na.lowerBound))
                label = String(label[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let fold = folded(label)
            if fold.isEmpty || fold == "dom" || fold.hasPrefix("prac") { continue }
            if fold.count >= 2 { return SavedPlacesStore.canonicalLabel(for: label) }
        }
        return nil
    }

    /// „na Wawel” / „na ulicę X” po słowie slotu; `nil` = bieżąca lokalizacja.
    private static func extractSavePlaceTargetQuery(from cleaned: String, lower: String, slotWord: String) -> String? {
        // „zmień dom na …” / „zapisz dom jako …” już obsłużone etykietą — tu cel geokodu.
        if let r = lower.range(of: #"\bna\s+"#, options: .regularExpression) {
            let after = String(cleaned[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let foldAfter = folded(after)
            // „na mojej lokalizacji” / „na teraz” → current
            if foldAfter.hasPrefix("moj") || foldAfter.hasPrefix("teraz") || foldAfter.hasPrefix("tej lokal")
                || foldAfter.hasPrefix("aktualn") {
                return nil
            }
            // Nie traktuj „jako …” jako lokalizacji
            if foldAfter.hasPrefix("jako") { return nil }
            if after.count >= 2 { return after }
        }
        _ = slotWord
        return nil
    }

    /// „Chciałbym pojechać prosto na następnym skrzyżowaniu” / „skręć w lewo zamiast”.
    private static func extractPreferManeuver(_ lower: String) -> TurnDirection? {
        // Pytania o manewr („kiedy skręcić”) — nie zmiana trasy.
        if lower.contains("kiedy") || lower.contains("za ile") || lower.contains("gdzie mam")
            || lower.contains("gdzie skrecam") || lower.contains("jaki jest nastepny") {
            return nil
        }
        if (lower.contains("ukryj") || lower.contains("schowaj")) && lower.contains("kafelek") {
            return nil
        }

        // „po prostu” ≠ manewr „prosto”.
        let hasStraight =
            (!lower.contains("po prostu") && (
                lower.contains("jedz prosto") || lower.contains("jechac prosto")
                || lower.contains("pojechac prosto") || lower.contains("jade prosto")
                || lower.contains(" na prosto") || lower.contains("prosto na")
                || lower.hasPrefix("prosto") || lower.contains(" prosto")
                || lower.contains("na wprost")
            ))
            || lower.contains("nie skrecaj") || lower.contains("bez skretu")
            || lower.contains("go straight") || lower.contains("straight ahead") || lower.contains("keep straight")
        let hasLeft =
            lower.contains("w lewo") || lower.contains("na lewo")
            || lower.contains("turn left") || lower.contains("keep left") || lower.contains("bear left")
        let hasRight =
            lower.contains("w prawo") || lower.contains("na prawo")
            || lower.contains("turn right") || lower.contains("keep right") || lower.contains("bear right")

        let direction: TurnDirection?
        if hasStraight, !hasLeft, !hasRight {
            direction = .straight
        } else if hasLeft, !hasRight, !hasStraight {
            direction = .left
        } else if hasRight, !hasLeft, !hasStraight {
            direction = .right
        } else if hasStraight, (lower.contains("zamiast") || lower.contains("nie skrec")) {
            direction = .straight
        } else {
            direction = nil
        }
        guard let direction else { return nil }

        let explicitDesire =
            lower.contains("chcialbym") || lower.contains("chce ")
            || lower.contains("wolalbym") || lower.contains("wole ")
            || lower.contains("zamiast") || lower.contains("nie skrec")
            || lower.contains("zmien tras") || lower.contains("przelicz")
            || lower.contains("inna trasa") || lower.contains("innej trasy")
            || lower.contains("prefer") || lower.contains("rather")
            || lower.contains("pojechac") || lower.contains("jechac")
            || lower.contains("pojade") || lower.contains("jade ")
            || lower.contains("jedz prosto") || lower.contains("jedz w lewo") || lower.contains("jedz w prawo")
            || lower.contains("skrec w lewo") || lower.contains("skrec w prawo")

        let atIntersection =
            lower.contains("nastepn") || lower.contains("najblizsz")
            || lower.contains("skrzyz") || lower.contains("rond")
            || lower.contains("intersection") || lower.contains("roundabout")

        let duringNav = MapKitNavigationService.shared.mapState?.isNavigating == true
        if explicitDesire || atIntersection { return direction }
        if duringNav { return direction }
        return nil
    }

    private static func isNextTurnInfo(_ lower: String) -> Bool {
        // Unikaj kolizji z ukrywaniem kafelka skrętu / nawigacją „skręć w …”
        if (lower.contains("ukryj") || lower.contains("schowaj") || lower.contains("pokaz"))
            && lower.contains("kafelek") {
            return false
        }
        // Preferencja manewru ≠ pytanie o następny skręt.
        if extractPreferManeuver(lower) != nil { return false }
        if isNavigation(lower), lower.contains("jedz") || lower.contains("do ") || lower.contains("na ") {
            // „jedź na Wawel” ≠ pytanie o manewr
            if !lower.contains("kiedy") && !lower.contains("ktory") && !lower.contains("które")
                && !lower.contains("jakim") && !lower.contains("gdzie skrec")
                && !lower.contains("gdzie mam skrec") {
                return false
            }
        }

        let phrases = [
            "kiedy mam skrecic", "kiedy skrecam", "kiedy skrecic", "kiedy mam skrec",
            "kiedy nastepny skret", "kiedy jest skret", "za ile skrec", "za ile mam skrec",
            "gdzie mam skrecic", "gdzie skrecam", "gdzie skrecic", "gdzie jest skret",
            "na jakim skrzyzowaniu", "na jakim rondzie", "ktore rondo", "ktorym rondzie",
            "jakie skrzyzowanie", "jakim skrzyzowaniu", "na ktorej ulicy skrec",
            "jaki jest nastepny skret", "nastepny skret", "kolejny skret",
            "kiedy mam zjechac", "gdzie mam zjechac", "ktory zjazd",
            "when do i turn", "where do i turn", "next turn", "which roundabout"
        ]
        if phrases.contains(where: { lower.contains($0) }) { return true }

        let asksWhenWhere =
            lower.contains("kiedy") || lower.contains("gdzie") || lower.contains("jakim")
            || lower.contains("ktory") || lower.contains("ktore") || lower.contains("za ile")
        let turnWord =
            lower.contains("skrec") || lower.contains("skret") || lower.contains("rondo")
            || lower.contains("skrzyz") || lower.contains("zjazd") || lower.contains("zjedz")
            || lower.contains("manewr") || lower.contains("turn") || lower.contains("roundabout")
        return asksWhenWhere && turnWord
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
        let placeWord = lower.contains("ulic") || lower.contains("miejsc") || lower.contains("drog")
            || lower.contains("tej") || isAboutCurrentPlace(lower)
            || lower.contains(" ta ") || lower.contains("o ulic") || lower.contains("o tej")
            || lower.contains("okolic") || lower.contains("tutaj") || lower.contains("tu ")

        let historyWord = lower.contains("histori") || lower.contains("ciekawostk")
            || lower.contains("skad nazwa") || lower.contains("skąd nazwa")
            || lower.contains("od kiedy") || lower.contains("kiedy zbudowano")
            || lower.contains("co sie tu dzieje") || lower.contains("co się tu dzieje")
            || lower.contains("co tu bylo") || lower.contains("co tu było")
            || lower.contains("tlumaczenie nazwy") || lower.contains("co oznacza ta nazwa")
            || lower.contains("pochodzenie nazwy") || lower.contains("geneza")
            || lower.contains("patron") || lower.contains("na czyj") || lower.contains("na czyje")

        // „Opowiedz / powiedz coś o ulicy” → narracja historyczna, nie suchy adres.
        let narrativeAboutStreet = placeWord && (
            lower.contains("opowiedz") || lower.contains("opowiedz mi")
            || (lower.contains("powiedz") && (lower.contains("cos o") || lower.contains("coś o")
                || lower.contains(" o ulic") || lower.contains(" o tej") || lower.contains(" o tym")))
            || lower.contains("co wiesz o") || lower.contains("co ciekawego o")
        )

        if narrativeAboutStreet { return true }
        guard historyWord else { return false }
        return placeWord
    }

    private static func isRemainingTravelTime(_ lower: String) -> Bool {
        // Unikaj mylenia z paliwem / zasięgiem.
        if lower.contains("paliw") || lower.contains("bak") || lower.contains("litr")
            || lower.contains("zatank") || lower.contains("stacj") { return false }

        let timeWord = lower.contains("czas") || lower.contains("ile jeszcze")
            || lower.contains("ile zostalo") || lower.contains("ile zostało")
            || lower.contains("kiedy dojade") || lower.contains("kiedy dojadę")
            || lower.contains("kiedy bede") || lower.contains("kiedy będę")
            || lower.contains("eta") || lower.contains("dojedziemy")
            || lower.contains("dojade") || lower.contains("dojadę")
            || lower.contains("minut do") || lower.contains("godzin do")
            || lower.contains("pozostal") || lower.contains("pozostał")
            || lower.contains("do konca") || lower.contains("do końca")
            || lower.contains("do celu")

        guard timeWord else { return false }

        let routeWord = lower.contains("tras") || lower.contains("cel") || lower.contains("dojazd")
            || lower.contains("dojez") || lower.contains("dojeż") || lower.contains("podroz")
            || lower.contains("podróż") || lower.contains("jeszcze") || lower.contains("zostalo")
            || lower.contains("zostało") || lower.contains("konca") || lower.contains("końca")
            || lower.contains("eta") || lower.contains("przyjaz") || lower.contains("przyjazd")
            || lower.contains("dojade") || lower.contains("dojadę") || lower.contains("dojedziemy")

        // „ile czasu zostało” / „ile jeszcze” bez „paliwa” → ETA
        if lower.contains("ile jeszcze") || lower.contains("ile czasu")
            || lower.contains("ile zostalo czasu") || lower.contains("ile zostało czasu")
            || lower.contains("czasu do") || lower.contains("czas do") {
            return true
        }
        return routeWord
    }

    private static func isPosePuzzle(_ lower: String) -> Bool {
        // `lower` jest już po foldForMatching (ł→l, bez diakrytyków).
        // „łamigłówka” → „lamiglowka” (głó), nie „lamigowka”.
        let keys = [
            "lamiglowk", "lamigowk", "lamigufk", "lamigufka",
            "zagadk", "zagadke", "zagadka", "zagadki",
            "puzzle", "riddle", "quiz",
            "myslow", "myslenia", "do pomyslenia", "cos do myslenia",
            "daj zagadk", "daj lamig", "zadaj zagadk", "zadaj lamig",
            "chce zagadk", "chce lamig", "chcialbym zagadk", "chcialbym lamig",
            "porozwiazyw", "rozwiazujmy", "rozwiazywac", "rozwiazac zagadk",
            "zagrajmy w zagadk", "zagrajmy zagadk", "kolejna zagadk", "kolejna lamig",
            "nastepna zagadk", "nastepna lamig", "jeszcze zagadk", "jeszcze lamig",
            "opowiedz zagadk", "powiedz zagadk"
        ]
        return keys.contains(where: { lower.contains($0) })
    }

    /// Publiczne — używane też w VoiceCommandProcessor (ratunek przed odmową).
    static func looksLikePuzzleRequest(_ text: String) -> Bool {
        let lower = folded(text)
        if isRepeatPuzzle(lower) { return false }
        return isPosePuzzle(lower)
    }

    static func looksLikeRepeatPuzzle(_ text: String) -> Bool {
        isRepeatPuzzle(folded(text))
    }

    private static func isRepeatPuzzle(_ lower: String) -> Bool {
        let puzzleBit = lower.contains("zagadk") || lower.contains("lamig")
            || lower.contains("puzzle") || lower.contains("riddle")
        let repeatBit = lower.contains("powtorz") || lower.contains("powtórz")
            || lower.contains("powtorzenie") || lower.contains("jeszcze raz")
            || lower.contains("od poczatku") || lower.contains("od początku")
            || lower.contains("powiedz jeszcze raz") || lower.contains("przypomnij zagadk")
            || lower.contains("przypomnij lamig") || lower.contains("powtorz mi")
        if repeatBit && puzzleBit { return true }
        // Samo „powtórz” gdy czekamy na odpowiedź / jest lastPuzzle — obsługuje VoiceCommandProcessor.
        if puzzleBit && (lower.contains("ponownie") || lower.contains("znowu") || lower.contains("znow")) {
            return true
        }
        return false
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

    private static func isReadVisibleTile(_ lower: String) -> Bool {
        let readVerbs = [
            "przeczytaj", "przeczytaj mi", "przeczytaj to", "przeczytaj mi to",
            "odczytaj", "odczytaj mi", "odczytaj to", "odczytaj mi to",
            "przeczytaj kafelek", "przeczytaj kafel", "przeczytaj karte", "przeczytaj kartę",
            "co tu pisze", "co tu stoi", "co jest na kafelku", "co jest na kartce",
            "read this", "read the tile", "read the card"
        ]
        if readVerbs.contains(where: { lower.contains($0) }) { return true }
        // „przeczytaj mi” + wskazanie (to / ten / ta / kafelek)
        if (lower.contains("przeczyt") || lower.contains("odczyt"))
            && (lower.contains(" to") || lower.hasSuffix(" to") || lower.contains("ten ")
                || lower.contains("ta ") || lower.contains("kafel") || lower.contains("kart")
                || lower.contains("okienk") || lower.contains("panel")) {
            return true
        }
        return false
    }

    /// `true` = zwiększ przezroczystość (35% regular); `false` = zmniejsz (90% regular).
    private static func extractTilesTransparency(from lower: String) -> Bool? {
        let mentionsTransparency =
            lower.contains("przezroczyst") || lower.contains("przezroczystosc")
            || lower.contains("transparent") || lower.contains("liquid glass")
            || lower.contains("liquidglass") || lower.contains("szklo kafel")
            || lower.contains("szkła kafel") || lower.contains("szkla kafel")

        let mentionsTiles =
            lower.contains("kafel") || lower.contains("tile") || lower.contains("panel")
            || lower.contains("ui") || lower.contains("interfejs")

        // „zwiększ przezroczystość (kafelków)”
        if (lower.contains("zwieksz") || lower.contains("zwiększ") || lower.contains("zwiekszyc")
            || lower.contains("zwiększyć"))
            && mentionsTransparency {
            return true
        }
        // „zmniejsz przezroczystość (kafelków)”
        if (lower.contains("zmniejsz") || lower.contains("zmniejszyc") || lower.contains("zmniejszyć"))
            && mentionsTransparency {
            return false
        }

        // Parafrazy bez „zwiększ/zmniejsz”
        if mentionsTiles || mentionsTransparency {
            if lower.contains("bardziej przezroczyst") || lower.contains("bardziej transparent")
                || lower.contains("bardziej clear") || lower.contains("mocniej przezroczyst") {
                return true
            }
            if lower.contains("mniej przezroczyst") || lower.contains("mniej transparent")
                || lower.contains("bardziej widocz") || lower.contains("solidniejsz")
                || lower.contains("mocniejsze szkl") || lower.contains("mocniejsze glass")
                || lower.contains("gęstsze szkl") || lower.contains("gesto szkl")
                || lower.contains("regular glass") || lower.contains("90%") || lower.contains("80%") {
                return false
            }
        }
        return nil
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

    /// Ogólne pytanie o korki na trasie / w okolicy — bez konkretnej nazwy ulicy.
    private static func isGeneralRouteTrafficQuestion(_ lower: String) -> Bool {
        if lower.contains("spodziew") { return true }
        if lower.contains("szansa") && lower.contains("kork") { return true }
        if lower.contains("na trasie") || lower.contains("po drodze") || lower.contains("do celu") {
            return true
        }
        if lower.contains("gdzies") || lower.contains("gdzieś") { return true }
        // „czy są korki” / „będą korki” bez „korki na ul. X”
        if lower.contains("kork") || lower.contains("utrudn") {
            let namedStreet = lower.contains("ulic") || lower.contains("ul.")
                || (lower.contains(" na ") && !lower.contains("na trasie") && !lower.contains("na drodze"))
            return !namedStreet
        }
        return false
    }

    private static func isTraffic(_ lower: String) -> Bool {
        if lower.contains("korek") || lower.contains("korki") || lower.contains("utrudnien") {
            return true
        }
        if lower.contains("spodziew") && (lower.contains("kork") || lower.contains("ruch") || lower.contains("utrudn")) {
            return true
        }
        if lower.contains("szansa") && lower.contains("kork") { return true }
        if lower.contains("zakork") || lower.contains("utkne") || lower.contains("utknę") {
            return true
        }
        if lower.contains("ryzyko") && (lower.contains("kork") || lower.contains("ruch") || lower.contains("opozn")) {
            return true
        }
        if lower.contains("ruch") && (
            lower.contains("ulic") || lower.contains("drog") || lower.contains("tras")
            || lower.contains("doklad") || lower.contains("spodziew") || lower.contains("ocen")
        ) {
            return true
        }
        // „jak szybko dojadę”, „ile się stoi” — tylko poza paliwem.
        let travelTime = lower.contains("jak szybko") || lower.contains("ile sie stoi")
            || lower.contains("ile długo") || lower.contains("ile dlugo")
            || lower.contains("zakorkuje")
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
            "poprowadz", "prowadz", "pokieruj", "kieruj",
            "nawiguj", "nawigacja", "nawigacje", "nawigowaniu",
            "trasa", "trase", "dojazd", "dojazdu",
            "znajdz", "wyznacz",
            "dotrzec", "dojechac",
            "chcialbym dotrzec", "chce dotrzec", "chce dojechac",
            "lec", "lecimy",
            "konfiguruj trase", "ustaw trase", "ustaw nawigacje",
            "prowadz mnie", "poprowadz mnie", "zaprowadz mnie",
            "nawiguj mnie",
            "go to", "take me", "navigate", "navigate me", "drive to", "drive me",
            "directions to", "route to", "route me"
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
        if extractSavePlaceCommand(from: lower, lower: lower) != nil { return true }
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
        // Dłuższe frazy najpierw — matching na fold (ASR bez polskich znaków).
        let patterns = [
            "zaprowadz mnie prosze na ", "zaprowadz mnie prosze do ",
            "zaprowadz mnie na ", "zaprowadz mnie do ",
            "zaprowadz na ", "zaprowadz do ",
            "zabierz mnie na ", "zabierz mnie do ", "zabierz na ", "zabierz do ",
            "wez mnie na ", "wez mnie do ",
            "znajdz mi trase do ", "znajdz trase do ", "znajdz droge do ",
            "wyznacz trase do ",
            "pokieruj mnie na ", "pokieruj mnie do ", "pokieruj na ", "pokieruj do ",
            "kieruj mnie na ", "kieruj mnie do ", "kieruj na ", "kieruj do ",
            "poprowadz mnie prosze na ", "poprowadz mnie prosze do ",
            "poprowadz mnie na ", "poprowadz mnie do ", "poprowadz na ", "poprowadz do ",
            "prowadz mnie na ", "prowadz mnie do ", "prowadz na ", "prowadz do ",
            "nawiguj mnie prosze na ", "nawiguj mnie prosze do ",
            "nawiguj mnie na ", "nawiguj mnie do ", "nawiguj na ", "nawiguj do ",
            "trasa do ", "trase do ", "dojazd do ",
            "jedzmy na ", "jedzmy do ",
            "jedz prosze na ", "jedz prosze do ",
            "jedz na ", "jedz do ",
            "lec na ", "lec do ",
            "drive me to ", "take me to ", "navigate me to ", "navigate to ", "go to ",
            "route me to ", "directions to ",
            "do ", "na "
        ]
        let lower = folded(text)
        for pattern in patterns {
            if let range = lower.range(of: pattern) {
                // Odtwórz offset na oryginale przez fold — bierzemy ogon po wzorcu z folded.
                let destFold = String(lower[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if destFold.count > 1 {
                    // Preferuj oryginalną wielkość liter z końca wypowiedzi.
                    if let orig = text.range(of: destFold, options: .caseInsensitive)
                        ?? text.range(of: destFold.replacingOccurrences(of: "szkoly", with: "szkoły"), options: .caseInsensitive) {
                        return String(text[orig.lowerBound...])
                            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    }
                    return destFold
                }
            }
        }
        return nil
    }

    /// Usuwa wiodące słowa nawigacyjne, gdy wzorzec słownikowy nie trafił.
    private static func stripNavigationPrefix(_ text: String) -> String? {
        var fold = folded(text)
        let prefixes = [
            "zaprowadz mnie prosze", "zaprowadz mnie", "zaprowadz",
            "zabierz mnie", "zabierz", "wez mnie",
            "pokieruj mnie", "pokieruj", "kieruj mnie", "kieruj",
            "poprowadz mnie prosze", "poprowadz mnie", "poprowadz",
            "prowadz mnie", "prowadz",
            "nawiguj mnie prosze", "nawiguj mnie", "nawiguj",
            "znajdz mi trase", "znajdz trase",
            "wyznacz trase", "trasa", "trase", "dojazd",
            "jedzmy", "jedz prosze", "jedz",
            "lec", "take me", "drive me", "navigate me", "navigate", "go"
        ]
        for prefix in prefixes.sorted(by: { $0.count > $1.count }) {
            if fold.hasPrefix(prefix) {
                fold = String(fold.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                break
            }
        }
        for link in ["na ", "do ", "w strone ", "kierunek "] {
            if fold.hasPrefix(link) {
                fold = String(fold.dropFirst(link.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                break
            }
        }
        return fold.isEmpty ? nil : fold
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

        case .remainingTravelTime:
            return executeRemainingTravelTime()

        case .posePuzzle(let categoryRaw):
            let cat = categoryRaw.flatMap { DrivePuzzleService.Category(rawValue: $0) }
            return DrivePuzzleService.shared.pose(category: cat)

        case .repeatPuzzle:
            if let spoken = DrivePuzzleService.shared.repeatLast() {
                return spoken
            }
            return "Nie mam zagadki do powtórzenia. Powiedz „daj zagadkę”."

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

        case .setTilesTransparency(let moreTransparent):
            return DriveTileGlassStore.shared.setMoreTransparent(moreTransparent)

        case .readVisibleTile:
            return executeReadVisibleTile()

        case .recenterMap:
            return executeRecenterMap()

        case .setRecording(let enabled):
            return await DriveVoiceUIBridge.shared.setRecording(enabled: enabled)

        case .setVolume(let level, let delta):
            if let level {
                return DriveVoiceUIBridge.shared.setVolume(level)
            }
            if let delta {
                return DriveVoiceUIBridge.shared.adjustVolume(by: delta)
            }
            return "Powiedz na przykład: zwiększ głośność albo głośność na 50 procent."

        case .setTravelMode(let mode):
            return DriveVoiceUIBridge.shared.setTravelMode(mode)

        case .setOverlayMode(let ar, let compass):
            return executeOverlayMode(ar: ar, compass: compass)

        case .showCapabilities:
            return executeShowCapabilities()

        case .savePlace(let slot, let customLabel, let replaceExisting, let query):
            return await executeSavePlace(
                slot: slot,
                customLabel: customLabel,
                replaceExisting: replaceExisting,
                query: query
            )

        case .promptSavePlaceName(let label):
            let canonical = SavedPlacesStore.canonicalLabel(for: label)
            SavedPlaceNamePromptStore.shared.present(label: canonical)
            let hint: String = {
                switch SavedPlacesStore.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching(canonical)) {
                case "dom", "home": return "Wpisz adres domu"
                case "praca", "work": return "Wpisz adres pracy"
                default: return "Wpisz nazwę — \(canonical.lowercased())"
                }
            }()
            return "\(hint). Potem Zapisz albo Anuluj."

        case .downloadOfflineMaps:
            OfflineMapPromptStore.shared.present(
                around: MapKitNavigationService.shared.location?.coordinate
            )
            return "Wybierz obszar mapy offline na mapie — domyślnie 10 kilometrów wokół Ciebie — i zatwierdź Pobierz."

        case .traffic(let query):
            do {
                // „Czy gdzieś mogę się spodziewać korków?” → analiza aktywnej trasy + godzina.
                let navigating = MapKitNavigationService.shared.mapState?.isNavigating == true
                let routeFocused = query == nil || query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
                if navigating, routeFocused {
                    return await MapKitNavigationService.shared.analyzeActiveRouteTrafficRisk()
                }
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
                if navigating {
                    // Nazwa ulicy na trasie — i tak daj kontekst trasy.
                    return await MapKitNavigationService.shared.analyzeActiveRouteTrafficRisk(
                        focusHint: query
                    )
                }
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

        case .nextTurnInfo:
            return executeNextTurnInfo()

        case .preferManeuver(let direction):
            return await MapKitNavigationService.shared.reroutePreferringManeuver(direction)

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

            // Źródła: PRG/OGC + Nominatim + Wikipedia — narracja historyczna, bez kodów
            var body: String
            if let coordinate,
               let knowledge = await PolishStreetKnowledgeService.lookup(
                   coordinate: coordinate,
                   preferredName: title,
                   wantCuriosity: true
               ) {
                title = knowledge.streetName
                let place = knowledge.narrativePlaceLabel
                let district = knowledge.osmContext.map { " (okolica: \($0))" } ?? ""
                let wiki = knowledge.wikipediaExtract ?? ""

                if AssistantModelPolicy.usesFoundationModels,
                   (historical || knowledge.hasCuriosity),
                   #available(iOS 26.0, *),
                   let chat = CoreLM.makeChatSession() {
                    let sourceBlock = wiki.isEmpty
                        ? "Brak pewnego wpisu z Wikipedii — nie zmyślaj dat ani wydarzeń."
                        : "Źródło (możesz streścić, nie dodawaj faktów spoza tekstu):\n\(wiki)"
                    let note = (try? await CoreLM.honestReply(
                        to: """
                        Jesteś przewodnikiem w aucie. Opowiedz 2–4 krótkie zdania HISTORYCZNE o „\(place)”\(district) w Polsce.
                        Priorytet: pochodzenie / znaczenie nazwy, patron (jeśli ulica nosi imię osoby),
                        kiedy powstała lub co ważne wydarzyło się w okolicy, charakter historyczny miejsca.
                        \(sourceBlock)
                        Brzmij naturalnie. BEZ kodów TERYT/SIMC, kodów pocztowych i żargonu rejestrów.
                        Jeśli nie znasz pewnych faktów — powiedz to wprost.
                        """,
                        session: chat
                    )) ?? ""
                    if !note.isEmpty {
                        body = note
                    } else {
                        body = DeterministicBrainEngine.shared.narrateStreetHistory(
                            place: place,
                            wiki: wiki.isEmpty ? nil : wiki,
                            district: knowledge.osmContext
                        )
                    }
                } else {
                    body = DeterministicBrainEngine.shared.narrateStreetHistory(
                        place: place,
                        wiki: wiki.isEmpty ? nil : wiki,
                        district: knowledge.osmContext
                    )
                }
            } else if historical {
                if AssistantModelPolicy.usesFoundationModels,
                   #available(iOS 26.0, *),
                   let chat = CoreLM.makeChatSession() {
                    let note = (try? await CoreLM.honestReply(
                        to: """
                        Podaj 2–3 zdania o HISTORII lub pochodzeniu nazwy miejsca „\(title)”\(addressHint.isEmpty ? "" : " (\(addressHint))") w Polsce.
                        Naturalnie, bez kodów. Jeśli nie jesteś pewien faktów — powiedz to wprost.
                        Nie zmyślaj dat ani wydarzeń.
                        """,
                        session: chat
                    )) ?? ""
                    body = note.isEmpty
                        ? DeterministicBrainEngine.shared.narrateStreetHistory(
                            place: title,
                            wiki: nil,
                            district: addressHint.isEmpty ? nil : addressHint
                        )
                        : note
                } else {
                    body = DeterministicBrainEngine.shared.narrateStreetHistory(
                        place: title,
                        wiki: nil,
                        district: addressHint.isEmpty ? nil : addressHint
                    )
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
        guard MapKitNavigationService.shared.mapState != nil else {
            return "Nie mam aktywnej mapy do wyśrodkowania."
        }
        // Najpierw UI (wyjście z AR/kompasu), potem twarde snapnięcie kamery.
        DriveVoiceUIBridge.shared.request(.recenter)
        if MapKitNavigationService.shared.mapState?.isNavigating == true {
            return "Wyśrodkowuję widok na Tobie."
        }
        return "Wyśrodkowuję mapę na Tobie."
    }

    private static func executeOverlayMode(ar: Bool?, compass: Bool?) -> String {
        let travel = DriveVoiceUIBridge.shared.settings?.travelMode
            ?? (UserDefaults.standard.string(forKey: "travelMode").flatMap(TravelMode.init) ?? .car)
        let navigating = MapKitNavigationService.shared.mapState?.isNavigating == true

        if let ar {
            guard travel == .car else {
                return "Tryb AR jest dostępny w trybie samochodowym."
            }
            guard navigating else {
                return "Najpierw uruchom nawigację, potem włączę AR."
            }
            DriveVoiceUIBridge.shared.request(.setAR(ar))
            return ar ? "Włączam tryb AR." : "Wyłączam tryb AR."
        }
        if let compass {
            guard travel == .bike else {
                return "Kompas jest dostępny w trybie rowerowym."
            }
            guard navigating else {
                return "Najpierw uruchom nawigację, potem włączę kompas."
            }
            DriveVoiceUIBridge.shared.request(.setCompass(compass))
            return compass ? "Włączam tryb kompasu." : "Wyłączam tryb kompasu."
        }
        return "Powiedz: włącz AR, wyłącz AR, włącz kompas albo wyłącz kompas."
    }

    static let capabilityItems: [String] = [
        "Nawigacja Apple Maps — trasa, start z GPS lub innego miejsca",
        "Auto-przeliczanie trasy po zjeździe z drogi",
        "Zmiana manewru głosem — „chcę jechać prosto / w lewo na następnym skrzyżowaniu”",
        "Korki na trasie — „czy gdzieś mogę się spodziewać korków” (analiza ETA + godzina)",
        "Historia ulicy — „opowiedz o tej ulicy” / pochodzenie nazwy",
        "Ile czasu zostało do celu — „ile jeszcze czasu”",
        "Łamigówki — „nie wiem” = opcjonalna odpowiedź; „powtórz zagadkę”; kafelek do końca czytania",
        "Model deterministyczny offline — do pobrania w ustawieniach (na iPhone < 15 Pro domyślny)",
        "Losowe ciekawostki na hasło „powiedz ciekawostkę”",
        "Paliwo: poziom baku, zasięg, koszt trasy, stacje",
        "Najbliższa restauracja, sklep (Żabka, Lewiatan…) i stacja paliw",
        "Muzyka: pauza, play, następny, poprzedni / przewiń oraz głośność aplikacji",
        "Nagrywanie — włącz / wyłącz",
        "Tryb samochodowy / rowerowy, AR i kompas",
        "Wyśrodkowanie mapy i ukrywanie kafelków UI",
        "Kiedy i gdzie skręcić — rondo / skrzyżowanie",
        "Zmiana manewru — „chcę na następnym skrzyżowaniu jechać prosto / w lewo”",
        "Mapy offline — „pobierz mapy offline” (obszar ok. 10 km, wznawianie po utracie sieci)",
        "Przezroczystość kafelków — „zwiększ” / „zmniejsz przezroczystość kafelków”",
        "Odczyt kafelka — „przeczytaj mi to”",
        "Zapisane miejsca — dom, praca i własne (Siri: Navigate to Home in DriveMate)",
        "Przywrócenie przerwanej trasy"
    ]

    private static func executeSavePlace(
        slot: SavedPlaceSlot,
        customLabel: String?,
        replaceExisting: Bool,
        query: String?
    ) async -> String {
        let store = SavedPlacesStore.shared
        if !replaceExisting {
            if slot == .home, store.home != nil {
                return "Dom już mam zapisany. Powiedz „zmień mój dom”, albo usuń go w ustawieniach Drive Mate."
            }
            if slot == .work, store.work != nil {
                return "Pracę już mam zapisaną. Powiedz „zmień moją pracę”, albo usuń ją w ustawieniach Drive Mate."
            }
        }

        let coordinate: CLLocationCoordinate2D
        var resolvedAddress = ""
        var mapPlaceName = ""

        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let queries = await PlaceNameTranslator.searchQueries(from: query)
            var found = try? await MapKitNavigationService.shared.findFirstPlace(
                query: queries.primary,
                near: MapKitNavigationService.shared.location?.coordinate
            )
            if found == nil, queries.fallback != queries.primary {
                found = try? await MapKitNavigationService.shared.findFirstPlace(
                    query: queries.fallback,
                    near: MapKitNavigationService.shared.location?.coordinate
                )
            }
            guard let found else {
                return "Nie znalazłem miejsca „\(query)” do zapisania."
            }
            coordinate = CLLocationCoordinate2D(latitude: found.latitude, longitude: found.longitude)
            mapPlaceName = found.name
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            // Adres z nazwą (UKEN) — łatwiej znaleźć głosem i w ustawieniach.
            if found.address.localizedCaseInsensitiveContains(q) || found.name.localizedCaseInsensitiveContains(q) {
                resolvedAddress = found.address.isEmpty ? found.name : "\(found.name), \(found.address)"
            } else {
                resolvedAddress = found.address.isEmpty ? q : "\(q), \(found.address)"
            }
        } else {
            guard let here = MapKitNavigationService.shared.location?.coordinate else {
                return "Brak lokalizacji — nie zapiszę miejsca."
            }
            coordinate = here
            if let placemark = try? await MapKitNavigationService.shared.reverseGeocode(coordinate: here) {
                let street = [placemark.thoroughfare, placemark.subThoroughfare]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let city = placemark.locality ?? ""
                resolvedAddress = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
                if resolvedAddress.isEmpty {
                    resolvedAddress = placemark.name ?? ""
                }
            }
        }

        let label = (customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (slot == .custom ? (mapPlaceName.isEmpty ? slot.polishLabel : mapPlaceName) : slot.polishLabel)
        // Ciche EN — użytkownik tego nie widzi; Siri dostaje angielskie nazwy entity.
        let englishName = await PlaceNameTranslator.toEnglish(label)
        let englishAddress = resolvedAddress.isEmpty
            ? ""
            : await PlaceNameTranslator.toEnglish(resolvedAddress)

        let saved = store.upsert(
            slot: slot,
            label: label,
            englishName: englishName,
            address: resolvedAddress,
            englishAddress: englishAddress,
            coordinate: coordinate
        )
        let whereText: String = {
            if let query, !query.isEmpty {
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !mapPlaceName.isEmpty, mapPlaceName.caseInsensitiveCompare(q) != .orderedSame {
                    return "\(q) — \(mapPlaceName)"
                }
                return q
            }
            return saved.address.isEmpty ? "tej lokalizacji" : saved.address
        }()
        if replaceExisting || slot == .custom {
            return "Zapamiętałem: \(saved.label) to \(whereText). Powiedz „jedź do \(saved.label.lowercased())”."
        }
        return "Zapamiętałem \(saved.label.lowercased()) — \(whereText). Usuniesz to w ustawieniach Drive Mate."
    }

    private static func executeNextTurnInfo() -> String {
        let mapState = MapKitNavigationService.shared.mapState
        let coord = MapKitNavigationService.shared.location?.coordinate
        guard let mapState else {
            return "Nie mam aktywnej mapy nawigacji."
        }
        return mapState.spokenNextTurnAdvice(userCoordinate: coord)
    }

    private static func executeReadVisibleTile() -> String {
        guard let snap = DriveVisibleTileReader.currentSnapshot() else {
            return "Nie widzę teraz kafelka do przeczytania. Otwórz info, ofertę albo skręt — i powtórz."
        }
        if snap.holdsInfoCard {
            DriveInfoCardStore.shared.holdForReading()
        }
        return snap.speechText
    }

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

/// Pozostały czas do celu z aktywnej trasy — skala dystansu × expectedTravelTime.
private static func executeRemainingTravelTime() -> String {
    guard let mapState = MapKitNavigationService.shared.mapState,
          mapState.isNavigating,
          let route = mapState.route else {
        return "Nie mam aktywnej trasy — najpierw ustaw cel nawigacji."
    }

    let totalDistance = max(route.distance, 1)
    let totalTime = max(route.expectedTravelTime, 1)

    let remainingMeters: Double = {
        if let remaining = RouteGeometry.remainingDistanceMeters(
            along: route.polyline,
            from: MapKitNavigationService.shared.location?.coordinate
        ), remaining > 0 {
            return remaining
        }
        return totalDistance
    }()

    let fraction = min(1, max(0, remainingMeters / totalDistance))
    let seconds = totalTime * fraction
    let spoken = formatRemainingDuration(seconds)

    let dest = mapState.destinationTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if dest.isEmpty {
        return "Do końca trasy zostało około \(spoken)."
    }
    return "Do \(dest) zostało około \(spoken)."
}

private static func formatRemainingDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    if total < 45 { return "mniej niż minutę" }
    let minutes = (total + 30) / 60
    if minutes < 60 {
        if minutes == 1 { return "1 minutę" }
        if minutes % 10 >= 2 && minutes % 10 <= 4 && (minutes % 100 < 10 || minutes % 100 >= 20) {
            return "\(minutes) minuty"
        }
        return "\(minutes) minut"
    }
    let hours = minutes / 60
    let rem = minutes % 60
    let hourWord: String = {
        if hours == 1 { return "1 godzinę" }
        if hours % 10 >= 2 && hours % 10 <= 4 && (hours % 100 < 10 || hours % 100 >= 20) {
            return "\(hours) godziny"
        }
        return "\(hours) godzin"
    }()
    if rem == 0 { return hourWord }
    if rem == 1 { return "\(hourWord) i 1 minutę" }
    if rem % 10 >= 2 && rem % 10 <= 4 && (rem % 100 < 10 || rem % 100 >= 20) {
        return "\(hourWord) i \(rem) minuty"
    }
    return "\(hourWord) i \(rem) minut"
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

        // Znany alias (szkoła/dom/…) bez zapisu — nie zgaduj MapKit / innego miejsca.
        if SavedPlacesStore.isKnownRoleAlias(destination),
           SavedPlacesStore.shared.resolve(spokenQuery: destination) == nil {
            let label = SavedPlacesStore.canonicalLabel(for: destination)
            return "Nie mam jeszcze zapisanego miejsca „\(label)”. Powiedz „tutaj jest moja \(label.lowercased())” albo „zapamiętaj moją \(label.lowercased())”."
        }

        // Dom / praca / zapisane miejsce — od razu po współrzędnych.
        if let saved = SavedPlacesStore.shared.resolve(spokenQuery: destination) {
            let first = MapKitNavigationService.PlaceResult(
                name: saved.label,
                address: saved.address,
                latitude: saved.latitude,
                longitude: saved.longitude,
                category: "saved"
            )
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
                return await startRoute(to: first, fromLatitude: nil, fromLongitude: nil, startLabel: "Twojej lokalizacji")
            case .place(let startQuery):
                guard let origin = try? await MapKitNavigationService.shared.findFirstPlace(
                    query: startQuery,
                    near: MapKitNavigationService.shared.location?.coordinate
                ) else {
                    MapKitNavigationService.shared.setPendingDestination(first)
                    return "Cel: \(first.name). Nie znalazłem startu „\(startQuery)”. Skąd jedziemy?"
                }
                return await startRoute(
                    to: first,
                    fromLatitude: origin.latitude,
                    fromLongitude: origin.longitude,
                    startLabel: origin.name
                )
            case nil:
                if UserDefaults.standard.bool(forKey: "alwaysUseMyLocation") {
                    return await startRoute(to: first, fromLatitude: nil, fromLongitude: nil, startLabel: "Twojej lokalizacji")
                }
                MapKitNavigationService.shared.setPendingDestination(first)
                return "\(first.name). Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?"
            }
        }

        do {
            let queries = await PlaceNameTranslator.searchQueries(from: destination)
            var first = try await MapKitNavigationService.shared.findFirstPlace(
                query: queries.primary,
                near: MapKitNavigationService.shared.location?.coordinate
            )
            if first == nil, queries.fallback != queries.primary {
                first = try await MapKitNavigationService.shared.findFirstPlace(
                    query: queries.fallback,
                    near: MapKitNavigationService.shared.location?.coordinate
                )
            }
            guard let first else {
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
