import Foundation

/// Wspólne czyszczenie wypowiedzi pod ekstrakcję miejsca/ulicy.
///
/// Bez tego „co to za ulica Wawelska?” trafiało do wyszukiwarki jako
/// „ulica Wawelska” z pytajnikiem, a „opowiedz o tej ulicy” jako „tej ulicy” —
/// czyli w nic. Tutaj zdejmujemy wypełniacze i interpunkcję.
enum DriveIntentQueryHelpers {

    /// Folding z poprawną obsługą polskiego „ł”.
    ///
    /// `String.folding(options: .diacriticInsensitive, locale: pl_PL)` NIE zamienia
    /// „ł” na „l” — to nie jest diakrytyka, lecz odrębna litera alfabetu.
    /// Wszystkie tabele słów kluczowych w Drive Mate pisane są bez „ł”
    /// („glodny”, „sluchac”, „wlacz”), więc z oryginalnym foldingiem ASR zwracające
    /// „głodny” albo „słuchaj” nigdy nie trafiało w tabelę. To główna przyczyna
    /// „raz rozumie, raz nie” — wszystko zależało od tego, czy dyktat zachował „ł”.
    static func foldForMatching(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "L")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
    }

    /// Wyrazy, które nigdy nie są nazwą miejsca.
    private static let stopWords: Set<String> = [
        "co", "czym", "jak", "jaka", "jakie", "jaką", "jaki", "który", "ktora", "która",
        "ktore", "które", "jaki", "jaka", "jakie", "ile", "gdzie", "kiedy", "czemu",
        "powiedz", "powiedz mi", "opowiedz", "opowiedz mi", "opisz", "opisz mi",
        "wiesz", "wiadomo", "informacje", "informacja", "info", "dane", "wiadomosci",
        "charakterystyka", "opis", "historia", "historie", "historię", "ciekawostka",
        "ciekawostki", "ciekawostkę", "szczegoly", "szczegóły", "powiedz mi o",
        "mi", "mnie", "nam", "nam", "prosze", "proszę", "szybko", "teraz", "jeszcze",
        "takze", "także", "wlasnie", "właśnie", "naprawde", "naprawdę", "chyba",
        "o", "w", "na", "do", "z", "ze", "za", "po", "przy", "pod", "przed", "za",
        "ta", "ta", "tej", "ten", "to", "te", "tych", "tam", "tu", "tutaj", "tutajszym",
        "obec", "obecnie", "obecnej", "obecnego", "aktualnie", "aktualna", "aktualnej",
        "ulica", "ulicy", "ulice", "ulicę", "ulicą", "ulice", "ulice", "ulicy",
        "miejscowosc", "miejscowości", "miejscowosc", "miejsce", "miejsca", "miejscu",
        "droga", "drogi", "droge", "drogę", "droga", "skrzyzowanie", "skrzyżowanie",
        "skrzyz", "skrzyż", "rondo", "plac", "osiedle", "osiedla", "dzielnica", "dzielnicy",
        "kwartal", "kwartał", "okolica", "okolice", "okolicy", "okolice", "rejon",
        "przystanek", "przystanku", "rond", "rondo", "jazda", "jazde", "dojazd", "dojazdu"
    ]

    /// Wyrazy, które NAJWYŻEJ mogą być częścią nazwy — nie usuwamy ich.
    private static let meaningfulSuffixes = ["ulicy", "ulica", "ulice", "poligon"]

    /// Zdejmuje wypełniacze, interpunkcję i duplikaty spójniki z nazwy ulicy/miejsca.
    static func cleanStreetQuery(_ raw: String) -> String {
        let text = raw
            .lowercased()
            .replacingOccurrences(of: "?", with: " ")
            .replacingOccurrences(of: "!", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        // UWAGA: celowo NIE foldujemy diakrytyków. Nazwy polskich ulic
        // naprawdę zawierają „ł” („Długa”, „Włókiennicza”), a MapKit szuka
        // je po oryginalnym zapisie. Tabela stopWords zawiera oba warianty.
        var words = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        // Usuwamy wypełniacze, ale NIE usuwamy ostatniej nazwy własnej.
        words = words.filter { word in
            if word.trimmingCharacters(in: CharacterSet.punctuationCharacters).isEmpty { return false }
            return !stopWords.contains(word)
        }

        // Odtwórz wielkość znaków: nazwę ulicy warto pokazać Wielkimi Literami.
        var result = ""
        for (index, word) in words.enumerated() {
            if index > 0 { result += " " }
            result += capitalized(deinflectStreetWord(word))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Zwraca nazwę ulicy z mianownika, żeby MapKit dostał „Długa”, a nie „Długą”.
    ///
    /// Polskie nazwy ulic są głównie żeńskie („ulica Długa”, „Wawelska”),
    /// więc wypowiedź brzmi „opisz ulicę Długą”. Obcięcie końcówki „ą” działa
    /// tylko po spółgłosce, więc nie tknie nazw typu „Piła” czy „Koło”.
    private static func deinflectStreetWord(_ word: String) -> String {
        guard word.count >= 3, word.hasSuffix("ą"), let beforeLast = word.dropLast().last else {
            return word
        }
        let isConsonant = !"aeiouyąęó".contains(beforeLast)
        guard isConsonant else { return word }
        return String(word.dropLast()) + "a"
    }

    /// Usuwa wiodące czasowniki nawigacyjne, zostawiając nazwę celu.
    static func stripNavigationWords(_ raw: String) -> String {
        var text = raw.lowercased().replacingOccurrences(of: "?", with: " ")
        let prefixes = [
            "zaprowadz mnie prosze", "zaprowadz mnie", "zaprowadz",
            "zabierz mnie", "zabierz", "wez mnie", "wez",
            "pokieruj mnie", "pokieruj", "kieruj mnie", "kieruj",
            "prowadz mnie", "prowadz", "nawiguj mnie", "nawiguj",
            "znajdz mi trase", "znajdz trase", "znajdz", "wyznacz trase", "wyznacz",
            "trasa", "trasę", "dojazd", "dojazdu", "jedzmy", "jedz prosze", "jedz",
            "pojedzmy", "pojedz", "lecimy", "lecmy", "lec",
            "chce dotrzec do", "chcialbym dotrzec do", "chce dojechac do",
            "chce dojechać do", "dotrzec do", "dojechac do", "dojechać do",
            "jak dojechac do", "jak dojechać do", "jak dojechać",
            "poprowadz mnie do", "poprowadź mnie do",
            "take me to", "drive me to", "navigate to", "go to"
        ]
        for prefix in prefixes {
            if text.hasPrefix(prefix + " ") {
                text = String(text.dropFirst(prefix.count + 1))
                break
            }
            if text == prefix { return "" }
        }
        for link in ["do ", "na ", "w strone ", "w stronę "] {
            if text.hasPrefix(link) {
                text = String(text.dropFirst(link.count))
                break
            }
        }
        // „z mojej lokalizacji” i inne ogony
        for marker in [" z mojej lokalizacji", " ze swojej lokalizacji", " z mojego punktu", " stad", " stąd"] {
            if let range = text.range(of: marker) {
                text = String(text[..<range.lowerBound])
                break
            }
        }
        let cleaned = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return capitalizedStreetName(cleaned)
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    /// „ulica wawelska” → „Ulica Wawelska” (wielka litera poza przyimkami).
    private static func capitalizedStreetName(_ text: String) -> String {
        let lowercased = ["i", "w", "z", "na", "do", "od", "przy", "nad", "pod", "przed", "za"]
        return text
            .split(separator: " ")
            .enumerated()
            .map { index, word -> String in
                let w = String(word)
                if index > 0, lowercased.contains(w.lowercased()) { return w }
                return capitalized(w)
            }
            .joined(separator: " ")
    }
}