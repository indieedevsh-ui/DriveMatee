import Foundation

/// Modele i generator paczki — bez zależności od silnika / PackService (unika cykli kompilacji).
enum DeterministicBrainPackBuilder {
struct Pack: Codable {
    var version: Int
    var synonymClusters: [String: [String]]
    var acceptExpansions: [String: [String]]
    var rejectExpansions: [String: [String]]
    var wordBanks: [String: [String]]
    var puzzleSeeds: [PuzzleSeed]
    var trivia: [String]
    var streetHistoryTemplates: [String]
    var chatReplies: [ChatRule]
    var fillerReplies: [String]
}

struct PuzzleSeed: Codable, Identifiable {
    var id: String
    var category: String
    var prompt: String
    var acceptKeys: [String]
    var rejectKeys: [String]
    var numericAnswer: Double?
    var numericTolerance: Double
    var acceptHint: String
    var rejectHint: String
    /// Szablon z placeholderami `{creature}`, `{place}` itd.
    var promptTemplate: String?
    var slotBanks: [String: String]?
}

struct ChatRule: Codable {
    var anyOf: [String]
    var replies: [String]
}


    static func buildInstallablePack() -> Pack {
        var pack = seedPack()
        pack = expandPack(pack)
        pack.version = 3
        return pack
    }

    static func encodeFullPack() throws -> Data {
        try JSONEncoder().encode(buildInstallablePack())
    }

// MARK: - Seed + expand

static func seedPack() -> Pack {
    Pack(
        version: 1,
        synonymClusters: baseSynonyms(),
        acceptExpansions: baseAcceptExpansions(),
        rejectExpansions: baseRejectExpansions(),
        wordBanks: baseWordBanks(),
        puzzleSeeds: basePuzzleSeeds(),
        trivia: baseTrivia(),
        streetHistoryTemplates: [
            "Z źródeł historycznych:",
            "W skrócie o przeszłości:",
            "Historycznie:",
            "Co do pochodzenia nazwy i historii:"
        ],
        chatReplies: baseChatRules(),
        fillerReplies: [
            "Jasne — mogę opowiedzieć ciekawostkę albo dać łamigówkę. Powiedz tylko którą.",
            "Słucham. Mogę pomóc z trasą, czasem do celu, historią ulicy albo zagadką.",
            "Bez problemu. Spróbuj: „ile jeszcze czasu”, „opowiedz o tej ulicy” albo „daj zagadkę”."
        ]
    )
}

static func expandPack(_ base: Pack) -> Pack {
    var pack = base
    // Doklej synonimy wariacyjne
    for (key, values) in base.synonymClusters {
        var expanded = Set(values)
        for v in values {
            expanded.insert(v)
            expanded.insert(v + "a")
            if v.count > 4 { expanded.insert(String(v.dropLast()) + "y") }
        }
        pack.synonymClusters[key] = Array(expanded).sorted()
    }
    // Wygeneruj warianty puzzle z szablonów
    var generated: [PuzzleSeed] = pack.puzzleSeeds
    let templateSeeds = pack.puzzleSeeds.filter { $0.promptTemplate != nil }
    for seed in templateSeeds {
        for i in 0..<4 {
            var copy = seed
            copy.id = "\(seed.id)-gen\(i)"
            generated.append(copy)
        }
    }
    pack.puzzleSeeds = generated
    // Więcej trivia z kombinatorów krótkich faktów
    pack.trivia.append(contentsOf: generatedTriviaExtras())
    return pack
}

static func baseSynonyms() -> [String: [String]] {
    [
        "nic": ["pustka", "puste rece", "puste ręce", "brak", "zero", "powietrze", "niczego"],
        "prom": ["prom rzeczny", "lodz", "łódź", "tratwa", "przeprawa", "przewoznik", "przewoźnik"],
        "lilia": ["lisc", "liść", "lilie wodne", "pad", "plaz"],
        "lod": ["lód", "zamarz", "zima", "crust", "tafla"],
        "pomoc": ["pomoz", "pomóż", "ktoz pomoze", "rybak", "ktoz", "ktoś"],
        "rosnie": ["rosnie", "rośnie", "wiecej", "więcej", "ciezszy", "cięższy", "pozorna sila", "przyspieszenie"],
        "zapalka": ["zapałka", "zapalki", "match", "najpierw zapalka"],
        "parowanie": ["ewapor", "mokra szmata", "wilgot", "wiat", "chlodzenie wyparne"],
        "proznia": ["próżnia", "vacuum", "brak powietrza", "bez powietrza", "osrodek", "ośrodek"],
        "stoi": ["zatrzymany", "zepsuje stoi", "dwa razy", "2 razy"],
        "drugi": ["co powiedzialby", "tamten", "drugiego", "zapytaj o drugiego"],
        "wygnany": ["wygoncie", "wygnacie", "zostane wygnany", "wyrzucicie"],
        "mostek z patyk": ["zbuduj most", "most z patykow", "mostek z patykow", "inzynieria zaby"],
        "teleport": ["przenies mnie", "magia przenoszenia", "zaklecie"],
        "latam": ["polece", "skrzydla", "naucze sie latac"]
    ]
}

static func baseAcceptExpansions() -> [String: [String]] {
    [
        "5": ["piec", "pięć", "piatka", "piątka", "piatek"],
        "45": ["czterdziesci piec", "czterdzieści pięć", "czterdziesci pięć"],
        "jech": ["od razu", "rusz", "nie czek", "proba", "spróbuj jechac"],
        "pustke": ["nic", "puste", "brak rzeczy", "nie niosę nic"]
    ]
}

static func baseRejectExpansions() -> [String: [String]] {
    [
        "mostek z patyk": ["zbuduje most", "zbuduj mostek", "most z drewna", "skleci most"],
        "teleport": ["przeniesienie", "portal", "zaklecie teleport"],
        "zabij": ["zabije smoka", "mieczem smoka", "atak na smoka"]
    ]
}

static func baseWordBanks() -> [String: [String]] {
    [
        "creature": ["żaba", "lis", "kruk", "smok", "troll", "kotek", "wiewiórka", "żółw", "sowa", "ryba"],
        "place": ["rzeka", "jezioro", "wąwóz", "most", "las", "bagno", "góra", "jaskinia", "miasto", "wieża"],
        "object": ["kamień", "liść", "lina", "lustro", "klucz", "latarnia", "księga", "zegar", "moneta", "mapa"],
        "virtue": ["odwagę", "cierpliwość", "prawdę", "pokorę", "ciszę", "wolność", "ciekawość"],
        "element": ["wiatr", "lód", "woda", "cień", "ogień", "piasek", "mgła"],
        "scientist": ["fizyk", "chemik", "biolog", "astronom", "geolog"],
        "numberA": ["3", "4", "5", "6", "7", "8"],
        "numberB": ["2", "3", "4", "5"]
    ]
}

static func basePuzzleSeeds() -> [PuzzleSeed] {
    var seeds: [PuzzleSeed] = [
        PuzzleSeed(
            id: "frog-river", category: "fantasy",
            prompt: "Żaba stoi nad szeroką rzeką. Nie umie pływać daleko, nie ma skrzydeł i nie może rosnąć. Co może zrobić, żeby znaleźć się po drugiej stronie — realnie w świecie bajki, ale bez budowania mostów z patyków ani czarów „przenieś mnie”?",
            acceptKeys: ["prom", "lilia", "lisc", "kloda", "lod", "przepraw", "pomoc", "kamien", "susza", "zima"],
            rejectKeys: ["mostek z patyk", "zbuduj most", "teleport", "latam", "wykop tunnel"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Pasuje — wykorzystanie tego, co już jest (liść, kłoda, lód, przeprawa, pomoc).",
            rejectHint: "Żaba nie zbuduje mostu jak inżynier. Szukaj rozwiązania z natury albo gotowej przeprawy.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "dragon-bridge", category: "fantasy",
            prompt: "Smok pilnuje mostu i mówi: „Przepuszczę tylko kogoś, kto niesie rzecz, której ja — smok — nigdy nie mogę posiadać”. Co niesiesz? Magia przenoszenia i zabijanie smoka odpadają.",
            acceptKeys: ["nic", "pustke", "powietrz", "cien", "pokore", "prawde", "wolnosc", "imie"],
            rejectKeys: ["miecz", "zabij", "latam", "zloto", "teleport"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Smok nie „posiada” pustki, twojego cienia ani wolności wyboru.",
            rejectHint: "Siła i omijanie zagadki nie liczą się.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "parking-cars", category: "math",
            prompt: "Na parkingu jest rząd miejsc: co drugie zajęte przez czerwone auto, a między każdą parą czerwonych stoi jedno niebieskie. Jeśli czerwonych jest 6, ile jest niebieskich — rząd zaczyna się i kończy czerwonym?",
            acceptKeys: ["5", "piec"],
            rejectKeys: ["nieskoncz", "magicz"],
            numericAnswer: 5, numericTolerance: 0.1,
            acceptHint: "Między 6 czerwonymi jest 5 luk — 5 niebieskich.",
            rejectHint: "Pomyśl o lukach między czerwonymi autami.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "harmonic-speed", category: "math",
            prompt: "Trasa ma 3 odcinki po 10 km. Na pierwszym 30 km/h, na drugim 60, na trzecim 90. Jaka jest średnia prędkość na całej trasie — nie arytmetyczna średnia z 30, 60 i 90?",
            acceptKeys: ["45", "harmonicz"],
            rejectKeys: ["60", "180"],
            numericAnswer: 45, numericTolerance: 0.5,
            acceptHint: "Średnia harmoniczna ≈ 45 km/h.",
            rejectHint: "Średnia arytmetyczna 60 km/h tu kłamie.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "elevator-scale", category: "science",
            prompt: "W windzie stoisz na wadze i trzymasz piłkę. Winda rusza w górę z przyspieszeniem. Co dzieje się ze wskazaniem wagi — i dlaczego?",
            acceptKeys: ["rosnie", "wiecej", "ciezs", "przyspieszen", "pozorna"],
            rejectKeys: ["latam", "antygrawit"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Wskazanie rośnie — pozorna siła przy przyspieszeniu w górę.",
            rejectHint: "Przy starcie w górę nie jesteś lżejszy.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "match-first", category: "science",
            prompt: "Masz jedną zapałkę, świeczkę, kuchenkę gazową i lampę naftową. Co zapalasz najpierw?",
            acceptKeys: ["zapalka", "zapałk", "match"],
            rejectKeys: ["wszystko naraz"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Najpierw zapałkę.",
            rejectHint: "Bez zapałki nic nie wystartuje.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "clock-paradox", category: "philosophy",
            prompt: "Zegar, który stoi, i zegar spóźniony o godzinę. Który częściej pokazuje właściwy czas?",
            acceptKeys: ["stoi", "dwa razy", "2 razy", "zatrzymany"],
            rejectKeys: ["wyrzuc oba"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Zatrzymany ma rację dwa razy na dobę.",
            rejectHint: "Porównaj częstotliwość trafień.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "signpost", category: "philosophy",
            prompt: "Jeden drogowskaz zawsze kłamie, drugi zawsze mówi prawdę. Możesz zadać jedno pytanie do jednego. Jak trafić do miasta?",
            acceptKeys: ["drugi", "powiedzialby", "co powiedzialby"],
            rejectKeys: ["zapytam obu", "monet"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Zapytaj, co wskazałby drugi — i idź przeciwnie.",
            rejectHint: "Jedno pytanie musi unieważnić niewiedzę, który kłamie.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "king-paradox", category: "fantasy",
            prompt: "Król każe: jeśli zdanie prawdziwe — loch; jeśli fałszywe — wygnanie. Co mówisz, żeby zablokować wyrok?",
            acceptKeys: ["wygnany", "wygon", "wygnacie"],
            rejectKeys: ["zabijam krola", "milcze"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "„Zostanę wygnany” tworzy paradoks reguły.",
            rejectHint: "Szukaj zdania samoodnoszącego.",
            promptTemplate: nil, slotBanks: nil
        ),
        PuzzleSeed(
            id: "moon-sound", category: "science",
            prompt: "Dlaczego na Księżycu machanie ręką nie wytworzy dźwięku dla stojącego obok astronauty w prawdziwej próżni?",
            acceptKeys: ["proznia", "brak powietrza", "fal dzwiek", "osrodek"],
            rejectKeys: ["magicznie gluchy"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Dźwięk potrzebuje ośrodka — w próżni go nie ma.",
            rejectHint: "Klucz to brak powietrza.",
            promptTemplate: nil, slotBanks: nil
        )
    ]

    // Generatywne szablony (wypełniane z banków słów)
    seeds.append(contentsOf: [
        PuzzleSeed(
            id: "tpl-creature-place", category: "fantasy",
            prompt: "",
            acceptKeys: ["pomoc", "object", "element", "cierpliw", "poczek", "prom", "lisc"],
            rejectKeys: ["teleport", "mostek z patyk", "zabij"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Rozwiązanie ma być możliwe w świecie bajki bez nierealnej inżynierii.",
            rejectHint: "Unikaj magii „bo tak” i budowania mostów z niczego.",
            promptTemplate: "{creature} stoi przed {place}. Nie może latać ani rosnąć. Jak może dostać się dalej, używając tylko {object} albo {element} — bez czarów teleportacji?",
            slotBanks: ["creature": "creature", "place": "place", "object": "object", "element": "element"]
        ),
        PuzzleSeed(
            id: "tpl-virtue-dragon", category: "fantasy",
            prompt: "",
            acceptKeys: ["virtue", "nic", "pustke", "prawd", "pokor", "cisz", "woln"],
            rejectKeys: ["zabij", "miecz", "teleport"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Chodzi o coś, czego strażnik z natury „posiąść” nie może.",
            rejectHint: "Siła nie rozwiązuje tej zagadki.",
            promptTemplate: "Strażnik {place} przepuszcza tylko tego, kto niesie {virtue} albo rzecz, której sam nie może mieć. Co proponujesz — bez walki?",
            slotBanks: ["place": "place", "virtue": "virtue"]
        ),
        PuzzleSeed(
            id: "tpl-math-gaps", category: "math",
            prompt: "",
            acceptKeys: ["numberB"],
            rejectKeys: ["nieskoncz"],
            numericAnswer: nil, numericTolerance: 0.1,
            acceptHint: "Policz luki między elementami skrajnymi.",
            rejectHint: "To nie jest mnożenie całego rzędu.",
            promptTemplate: "Stoi {numberA} latarni w rzędzie. Między każdą parą są kwiaty — po jednym. Ile kwiatów, jeśli rząd zaczyna się i kończy latarnią?",
            slotBanks: ["numberA": "numberA"]
        ),
        PuzzleSeed(
            id: "tpl-science-observe", category: "science",
            prompt: "",
            acceptKeys: ["pomiar", "obserw", "hipotez", "eksperyment", "powtarz", "kontrol"],
            rejectKeys: ["magia", "wróż"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Nauka opiera się na obserwacji, hipotezie i sprawdzalnym eksperymencie.",
            rejectHint: "Szukaj metody naukowej, nie wróżby.",
            promptTemplate: "{scientist} widzi dziwne zjawisko przy {place}. Jak powinien sprawdzić, czy to realny efekt, a nie przypadek — jednym zdaniem?",
            slotBanks: ["scientist": "scientist", "place": "place"]
        ),
        PuzzleSeed(
            id: "tpl-philosophy-choice", category: "philosophy",
            prompt: "",
            acceptKeys: ["odpowiedz", "odpowiedzial", "konsekwen", "uczciw", "prawd", "wybor", "wybór"],
            rejectKeys: ["rzut moneta bez myslenia"],
            numericAnswer: nil, numericTolerance: 0,
            acceptHint: "Ważne są konsekwencje wyboru i uczciwość wobec reguły.",
            rejectHint: "Nie chodzi o losowanie bez namysłu.",
            promptTemplate: "Musisz wybrać: chronić {object} albo dotrzymać obietnicy danej przy {place}. Jak uzasadnisz decyzję w jednym zdaniu — bez unikania dylematu?",
            slotBanks: ["object": "object", "place": "place"]
        )
    ])
    return seeds
}

static func baseTrivia() -> [String] {
    // Bazowy zestaw — pełna paczka dokłada extras przy instalacji.
    [
        "Wisła ma około 1047 km — to najdłuższa rzeka w Polsce.",
        "Bałtyk jest mniej słony niż oceany, bo wpływa do niego dużo rzek.",
        "GPS liczy pozycję z czasu sygnału satelitów — nie z „mapy w telefonie”.",
        "Średnia harmoniczna prędkości nie jest równa średniej arytmetycznej odcinków.",
        "Dźwięk nie niesie się w próżni — potrzebuje ośrodka.",
        "Zatrzymany zegar ma rację dwa razy na dobę.",
        "Konstytucja 3 maja z 1791 to jedna z pierwszych nowoczesnych konstytucji w Europie.",
        "Kopernik opisał model heliocentryczny — Ziemia krąży wokół Słońca.",
        "ISS okrąża Ziemię mniej więcej co 90 minut.",
        "Honeybee wskazuje pokarm tańcem — kierunek i odległość.",
        "Mount Everest nadal rośnie przez zderzenie płyt tektonicznych.",
        "Neutrina prawie nie oddziałują z materią.",
        "Bursztyn bałtycki to skamieniała żywica sprzed milionów lat.",
        "Pierwsze światła drogowe powstały jeszcze przed erą samochodów.",
        "Księżyc oddala się od Ziemi o kilka centymetrów rocznie."
    ]
}

static func generatedTriviaExtras() -> [String] {
    let subjects = ["Wisła", "Odra", "Tatry", "Bałtyk", "Wawel", "Gdańsk", "Warszawa", "Kraków"]
    let predicates = [
        "ma bogatą historię handlu i transportu",
        "był ważnym punktem na mapach od wieków",
        "łączy kulturę, geografię i codzienne trasy ludzi",
        "pojawia się w przewodnikach jako symbol regionu"
    ]
    var out: [String] = []
    for s in subjects {
        for p in predicates {
            out.append("\(s) \(p) — warto o tym pamiętać w podróży.")
        }
    }
    let science = [
        "Przy przyspieszeniu windy w górę wskazanie wagi rośnie — to siła pozorna.",
        "Parowanie wody zabiera ciepło — stąd chłodzenie mokrą szmatką na wietrze.",
        "Światło w próżni porusza się najszybciej ze znanych sygnałów informacyjnych.",
        "Liczby pierwsze to liczby większe od 1 dzielące się tylko przez 1 i siebie.",
        "Mapa nie jest terenem — to model; stąd uproszczenia w nawigacji."
    ]
    out.append(contentsOf: science)
    return out
}

static func baseChatRules() -> [ChatRule] {
    [
        ChatRule(anyOf: ["kim jestes", "kim jesteś", "co potrafisz", "co umiesz"],
                 replies: [
                    "Jestem Drive Mate. Pomagam w trasie, korkach, historii ulicy, czasie do celu, łamigówkach i ciekawostkach.",
                    "Drive Mate — nawigacja, paliwo, ulice, zagadki i ciekawostki. Powiedz, czego potrzebujesz."
                 ]),
        ChatRule(anyOf: ["dziekuje", "dziękuję", "dzieki", "thanks"],
                 replies: ["Nie ma za co.", "Jasne — jadę z Tobą dalej.", "Proszę."]),
        ChatRule(anyOf: ["jak sie masz", "jak się masz", "co u ciebie"],
                 replies: [
                    "Gotowy do drogi. Mogę dać zagadkę albo sprawdzić czas do celu.",
                    "W porządku — słucham komend. Chcesz ciekawostkę?"
                 ]),
        ChatRule(anyOf: ["nudze", "nudze", "jest nudno", "zrob cos"],
                 replies: [
                    "Mogę dać łamigówkę albo ciekawostkę — powiedz którą.",
                    "Spróbujmy zagadki fantasy albo naukowej. Która wersja?"
                 ]),
        ChatRule(anyOf: ["pogoda"],
                 replies: [
                    "Nie mam tu live pogody jak aplikacja pogodowa — mogę za to pomóc z trasą i czasem do celu."
                 ]),
        ChatRule(anyOf: ["zart", "dowcip"],
                 replies: [
                    "Dlaczego GPS nigdy się nie gubi? Bo zawsze wie, gdzie jest satelita — a ja wiem, gdzie cel.",
                    "Kierowca pyta mapę: „ile jeszcze?”. Mapa: „zależy, czy skręcisz w tę historię, czy w tamtą ulicę”."
                 ])
    ]
}
}

