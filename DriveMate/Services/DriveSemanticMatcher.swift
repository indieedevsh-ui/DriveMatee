import Foundation
import NaturalLanguage

/// Dopasowanie semantyczne wypowiedzi do intencji Drive Mate.
///
/// Słownik w `DriveIntentParser` łapie tylko konkretne komendy. Ten moduł łapie
/// PARAFRAZY: wektorowa miara podobieństwa (NLEmbedding) między wypowiedzią
/// a grupą przykładowych zdań dla danej intencji. Dzięki temu „sporo mi zostało”
/// trafia tam samo, co „ile mam paliwa”, a „co to za ulica” tam samo, co
/// „powiedz mi o tej ulicy”.
///
/// Działa w pełni offline — model językowy NaturalLanguage jest wbudowany w iOS.
enum DriveSemanticMatcher {

    /// Proponowana intencja + pewność. `score` to średnia z najlepszych trafień.
    struct Match {
        let intent: DriveIntent
        let score: Double
    }

    /// Grupy przykładów. Krótsze frazy = mniej szumu; pełne zdania uczą sensu.
    private enum Concept {
        case fuelCost
        case fuelLevel
        case fuelRange
        case fuelStation
        case cheapestFuel
        case whereAmI
        case streetInfo
        case streetHistory
        case traffic
        case food
        case navigation
        case speedLimit
        case cancelRoute
        case musicPause
        case musicNext
        case musicPrevious
        case setCarModel
        case pastVisit
        case chromeVisibility
        case recenterMap
        case showCapabilities
        case restoreRoute
        case cancelListening
        case tellTrivia
    }

    private static let anchors: [Concept: [String]] = [
        .fuelCost: [
            "ile kosztuje przejazd paliwem",
            "koszt paliwa na tej trasie",
            "ile zapłacę za benzynę",
            "ile litrów paliwa zużyjemy",
            "jakie jest spalanie na trasie",
            "ile paliwa zużywa moje auto",
            "podaj koszt paliwa do celu",
            "ile wyjdzie za paliwo",
            "jaki koszt ma ta trasa w paliwie",
            "ile mi to paliwa zużyje ta trasa",
            "ile paliwa zużyje ta trasa",
            "ile spalę na tej trasie"
        ],
        .fuelLevel: [
            "ile paliwa mam w baku",
            "jaki jest poziom paliwa",
            "pokaż poziom paliwa",
            "ile procent paliwa zostało",
            "czy bak jest pełny",
            "stan paliwa",
            "ile mam paliwa w baku",
            "czy muszę zatankować",
            "czy wystarczy mi paliwa",
            "czy starczy paliwa na rezerwie"
        ],
        .fuelRange: [
            "na ile kilometrów wystarczy paliwo",
            "jaki jest zasięg auta",
            "jak daleko dojadę",
            "dowieziesz mnie do celu",
            "czy dojadę na rezerwie",
            "jak daleko pojadę na obecnym paliwie",
            "zasięg przy obecnym poziomie",
            "czy wystarczy mi tego na trasę",
            "dowiezie mnie na wypadek"
        ],
        .fuelStation: [
            "znajdź stację paliw",
            "gdzie zatankować",
            "najbliższa stacja benzynowa",
            "pokaż mi stację paliw",
            "potrzebuję zatankować",
            "gdzie jest najbliższy orlen",
            "szukaj stacji paliw w okolicy",
            "na której stacji zatankować"
        ],
        .cheapestFuel: [
            "gdzie najtaniej zatankować",
            "najtańsza stacja paliw",
            "na której stacji paliwo jest najtańsze",
            "porównaj ceny paliwa",
            "gdzie najtaniej nalewać",
            "szukaj taniej stacji"
        ],
        .whereAmI: [
            "gdzie jestem",
            "jaki jest mój adres",
            "co to za miejsce",
            "jak się nazywa ta ulica",
            "w jakim mieście jestem",
            "powiedz mi gdzie się znajduję",
            "jaka ulica tu jest",
            "jaka jestem lokalizacja",
            "na jakiej ulicy stoję",
            "podaj mi mój adres"
        ],
        .streetInfo: [
            "co to za ulica",
            "informacje o tej ulicy",
            "powiedz coś o tej ulicy",
            "opisz tę ulicę",
            "dane o tej ulicy",
            "co wiesz o tej ulicy",
            "charakterystyka ulicy",
            "co tu się znajduje",
            "opisz okolicę",
            "opowiedz o tym miejscu"
        ],
        .streetHistory: [
            "historia tej ulicy",
            "skąd nazwa tej ulicy",
            "opowiedz historię ulicy",
            "ciekawostka o tej ulicy",
            "kiedy zbudowano tę ulicę",
            "co się tu wydarzyło",
            "historia tego miejsca",
            "ciekawostki o tym miejscu"
        ],
        .traffic: [
            "czy są korki",
            "jak wygląda ruch",
            "czy utrudnienia na trasie",
            "sprawdź korki w okolicy",
            "ocena ryzyka korków",
            "czy utknę",
            "jak szybko dojadę"
        ],
        .food: [
            "jestem głodny",
            "gdzie zjeść",
            "znajdź restaurację",
            "chce coś zjeść",
            "na obiad",
            "najbliższa knajpa",
            "szukam miejsca na śniadanie"
        ],
        .navigation: [
            "zaprowadź mnie",
            "chcę dojechać",
            "wyznacz trasę",
            "poprowadź mnie do",
            "jedź na",
            "potrzebuję dojechać do",
            "pokaż mi drogę do",
            "jak dojechać do"
        ],
        .speedLimit: [
            "jaka tu jest ograniczenie prędkości",
            "ile mogę jechać",
            "limit prędkości na tej drodze",
            "jaka jest maksymalna prędkość"
        ],
        .cancelRoute: [
            "anuluj trasę",
            "zakończ nawigację",
            "wyłącz trasę",
            "przerwij trasę",
            "jedziemy na złotym"
        ],
        .musicPause: [
            "zatrzymaj muzykę",
            "pauza",
            "wstrzymaj odtwarzacz",
            "wycisz muzykę"
        ],
        .musicNext: [
            "następny utwór",
            "kolejna piosenka",
            "pomiń tę piosenkę",
            "dalej"
        ],
        .musicPrevious: [
            "poprzedni utwór",
            "cofnij piosenkę",
            "graj poprzednią"
        ],
        .setCarModel: [
            "moje auto to Toyota Corolla",
            "jeżdżę Skodą Octavią",
            "mam samochód kombi",
            "zapisz mój model auta"
        ],
        .pastVisit: [
            "jedź tam gdzie byłem wczoraj",
            "zabierz mnie w miejsce odwiedzone dwa dni temu",
            "tam gdzie ostatnio jechałem"
        ],
        .chromeVisibility: [
            "ukryj prędkościomierz",
            "pokaż zegar",
            "schowaj kafelek",
            "wyłącz ten kafelek",
            "przywróć kafelek wyśrodkuj"
        ],
        .recenterMap: [
            "wyśrodkuj mi widok",
            "wyśrodkuj mapę",
            "centruj widok",
            "wycentruj na mnie",
            "wyśrodkuj kamerę",
            "wróć do mojej lokalizacji na mapie",
            "pokaż mnie na mapie",
            "recenter map"
        ],
        .showCapabilities: [
            "co potrafisz",
            "co umiesz",
            "jakie masz umiejętności",
            "w czym możesz pomóc",
            "co drive mate umie",
            "jakie masz funkcje",
            "lista komend",
            "what can you do"
        ],
        .restoreRoute: [
            "przywróć poprzednią trasę",
            "wznów przerwaną trasę",
            "jedź dalej tą trasą",
            "cofnij trasę"
        ],
        .cancelListening: [
            "przestań słuchać",
            "wyłącz asystenta",
            "anuluj nasłuchiwanie",
            "zamknij drive mate"
        ],
        .tellTrivia: [
            "powiedz mi jakąś ciekawostkę",
            "opowiedz ciekawostkę",
            "daj ciekawostkę",
            "powiedz coś ciekawego",
            "chcę usłyszeć ciekawostkę",
            "losowa ciekawostka"
        ]
    ]

    /// Próg akceptacji podobieństwa. Niżej = odważniej, ale więcej fałszywych trafień.
    private static let acceptanceThreshold = 0.42

    /// Progi per-Concept — paliwo i ulica bywały najgorszym problemem, więc traktujemy je priorytetowo.
    private static func threshold(for concept: Concept) -> Double {
        switch concept {
        case .fuelCost, .fuelLevel, .fuelRange, .fuelStation, .cheapestFuel,
             .streetInfo, .streetHistory, .whereAmI, .recenterMap, .showCapabilities:
            return acceptanceThreshold - 0.06
        case .navigation:
            // Nawigacja semantyczna bywa zbyt agresywna („widok” → miejsce).
            return acceptanceThreshold + 0.08
        default:
            return acceptanceThreshold
        }
    }

    private static let embedding: NLEmbedding? = {
        let pl = NLEmbedding.wordEmbedding(for: .polish)
        return pl ?? NLEmbedding.wordEmbedding(for: .english)
    }()

    /// Czy embedding jest dostępny — bez niego działamy wyłącznie na słowniku.
    static var isAvailable: Bool { embedding != nil }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [String: Double]] = [:]

    private static func similarity(_ a: String, _ b: String) -> Double {
        guard let embedding else { return 0 }
        return Double(1 - embedding.distance(between: a, and: b))
    }

    /// Wstępne podobieństwo semantyczne — bez budowania intencji.
    static func bestScores(for phrase: String) -> [String: Double] {
        guard let embedding else { return [:] }
        let input = phrase.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "pl_PL")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count >= 3 else { return [:] }

        cacheLock.lock()
        let cached = cache[input]
        cacheLock.unlock()
        if let cached { return cached }

        var result: [String: Double] = [:]
        let vectors = embedding.neighbors(
            for: input,
            maximumCount: 40,
            distanceType: .cosine
        )
        for concept in anchors.keys {
            guard let examples = anchors[concept] else { continue }
            var best = 0.0
            var running = 0.0
            var hits = 0
            for example in examples {
                var score = similarity(input, example)
                // Wektorowy sąsiad pojedynczego słowa bywa lepszy niż całe zdanie.
if score < 0.6, let bestWord = vectors.first?.0 {
                        score = max(score, similarity(bestWord, example))
                    }
                if score >= 0.3 { running += score; hits += 1 }
                best = max(best, score)
            }
            // Średnia kilku trafień > najlepsze pojedyncze zdanie: wierniejsze dla parafraz.
            let average = hits > 1 ? running / Double(hits) : best
            let score = (best + average) / 2
            if score > 0.2 { result[label(of: concept)] = score }
        }

        cacheLock.lock()
        if cache.count > 200 { cache.removeAll(keepingCapacity: true) }
        cache[input] = result
        cacheLock.unlock()
        return result
    }

    /// Najlepsza intencja dla wypowiedzi, gdy słownik nic nie znalazł.
    static func match(_ phrase: String, context: MatchContext) -> Match? {
        let scores = bestScores(for: phrase)
        guard !scores.isEmpty else { return nil }

        var candidates: [(Concept, Double)] = []
        for (label, score) in scores {
            guard let concept = concept(forLabel: label) else { continue }
            candidates.append((concept, score))
        }
        guard !candidates.isEmpty else { return nil }

        // Kontekst pomaga rozstrzygnąć bliźniacze grupy.
        for index in candidates.indices {
            if let adjusted = adjust(candidates[index].0, with: context, base: candidates[index].1) {
                candidates[index].1 = adjusted
            } else {
                candidates[index].1 = -1
            }
        }
        candidates.sort { $0.1 > $1.1 }

        guard let best = candidates.first, best.1 > 0 else { return nil }
        guard best.1 >= threshold(for: best.0) else { return nil }

        // Przewaga nad drugim miejscem — gdy remis, wolimy nie zgadywać.
        if candidates.count > 1, candidates[1].1 > 0 {
            let margin = best.1 - candidates[1].1
            if margin < 0.03, best.1 < 0.62 { return nil }
        }

        guard let intent = makeIntent(best.0, phrase: phrase) else { return nil }
        return Match(intent: intent, score: best.1)
    }

    /// Kontekst pomagający w rozstrzygnięciu wątpliwości.
    struct MatchContext {
        var isNavigating: Bool = false
        var isAskingAboutCurrentPlace: Bool = false

        static let neutral = MatchContext()
    }

    private static func adjust(_ concept: Concept, with context: MatchContext, base: Double) -> Double? {
        switch concept {
        case .fuelCost, .fuelRange:
            // Poza trasą „koszt przejazdu” i tak policzymy dla celu — nie odrzucaj.
            return base * 0.95
        case .restoreRoute, .cancelRoute:
            return context.isNavigating ? base : base * 0.6
        case .traffic:
            return base * (context.isNavigating ? 1.05 : 0.95)
        case .streetInfo, .whereAmI:
            return context.isAskingAboutCurrentPlace ? base * 1.05 : base
        default:
            return base
        }
    }

    // MARK: - Intents

    private static func makeIntent(_ concept: Concept, phrase: String) -> DriveIntent? {
        switch concept {
        case .fuelCost:
            return .fuelCost
        case .fuelLevel:
            return .fuelLevel
        case .fuelRange:
            return .fuelRange
        case .fuelStation:
            return .nearestFuel(preferCheapest: false)
        case .cheapestFuel:
            return .nearestFuel(preferCheapest: true)
        case .whereAmI:
            return .whereAmI
        case .streetInfo:
            return .streetInfo(query: nil)
        case .streetHistory:
            return .streetHistory(query: nil)
        case .traffic:
            return .traffic(query: nil)
        case .food:
            return .findFood
        case .navigation:
            let folded = DriveIntentQueryHelpers.foldForMatching(phrase)
            if DriveIntentParser.isNoiseOrFiller(folded) { return nil }
            if folded.contains("wysrodk") || folded.contains("centruj") || folded.contains("centrow") {
                return nil
            }
            let navHints = [
                "jedz", "nawig", "trasa", "trase", "zaprowadz", "zabierz", "dojazd",
                "dotrzec", "dojechac", "prowadz", "pokieruj", "kieruj", "wez mnie",
                "go to", "take me", "navigate", "drive to"
            ]
            guard navHints.contains(where: { folded.contains($0) }) else { return nil }
            let destination = DriveIntentQueryHelpers.stripNavigationWords(phrase)
            guard destination.count > 1 else { return nil }
            if DriveIntentParser.looksLikeUIOrCommandDestination(destination) { return nil }
            if DriveIntentParser.isNoiseOrFiller(DriveIntentQueryHelpers.foldForMatching(destination)) {
                return nil
            }
            return .navigate(destination: destination, start: nil)
        case .speedLimit:
            return .speedLimit
        case .cancelRoute:
            return .cancelRoute
        case .musicPause:
            return .music(.pause)
        case .musicNext:
            return .music(.next)
        case .musicPrevious:
            return .music(.previous)
        case .setCarModel:
            return .setCarModel(phrase)
        case .pastVisit:
            return .navigateToPastVisit(daysAgo: 1)
        case .chromeVisibility:
            return nil
        case .recenterMap:
            return .recenterMap
        case .showCapabilities:
            return .showCapabilities
        case .restoreRoute:
            return .restoreInterruptedRoute
        case .cancelListening:
            return .cancelListening
        case .tellTrivia:
            return .tellTrivia
        }
    }

    private static func label(of concept: Concept) -> String {
        String(describing: concept)
    }

    private static func concept(forLabel label: String) -> Concept? {
        switch label {
        case "fuelCost": return .fuelCost
        case "fuelLevel": return .fuelLevel
        case "fuelRange": return .fuelRange
        case "fuelStation": return .fuelStation
        case "cheapestFuel": return .cheapestFuel
        case "whereAmI": return .whereAmI
        case "streetInfo": return .streetInfo
        case "streetHistory": return .streetHistory
        case "traffic": return .traffic
        case "food": return .food
        case "navigation": return .navigation
        case "speedLimit": return .speedLimit
        case "cancelRoute": return .cancelRoute
        case "musicPause": return .musicPause
        case "musicNext": return .musicNext
        case "musicPrevious": return .musicPrevious
        case "setCarModel": return .setCarModel
        case "pastVisit": return .pastVisit
        case "chromeVisibility": return .chromeVisibility
        case "recenterMap": return .recenterMap
        case "showCapabilities": return .showCapabilities
        case "restoreRoute": return .restoreRoute
        case "cancelListening": return .cancelListening
        case "tellTrivia": return .tellTrivia
        default: return nil
        }
    }

    // MARK: - Diagnostics

    /// Ranking dla podglądu w logach — najwyższy wynik na intencję.
    static func rankedDebug(_ phrase: String) -> [(String, Double)] {
        bestScores(for: phrase)
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { ($0.key, $0.value) }
    }
}