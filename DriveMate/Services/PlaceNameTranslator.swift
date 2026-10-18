import Foundation
import Translation

/// Ciche tłumaczenie PL → EN pod Siri / MapKit. Wyniku nigdy nie pokazujemy użytkownikowi.
enum PlaceNameTranslator {
    /// Szybkie aliasy slotów + Translation framework (fallback: oryginał).
    static func toEnglish(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let fold = DriveIntentQueryHelpers.foldForMatching(trimmed)
        if let mapped = knownAlias(fold) { return mapped }

        // Już wygląda na angielski — nie tłumacz ponownie.
        if looksPrimarilyEnglish(trimmed) { return trimmed }

        guard #available(iOS 26.0, *) else { return trimmed }

        do {
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: "pl"),
                target: Locale.Language(identifier: "en")
            )
            let response = try await session.translate(trimmed)
            let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? trimmed : out
        } catch {
            return trimmed
        }
    }

    /// Query do wyszukiwania: preferuj EN, zachowaj oryginał jako zapas w bridge.
    static func searchQueries(from spoken: String) async -> (primary: String, fallback: String) {
        let original = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = await toEnglish(original)
        if DriveIntentQueryHelpers.foldForMatching(english) == DriveIntentQueryHelpers.foldForMatching(original) {
            return (original, original)
        }
        return (english, original)
    }

    private static func knownAlias(_ fold: String) -> String? {
        // Zdejmij typowe ogony Siri EN/PL: „to my school”, „moja szkoła”.
        var key = fold
        for prefix in ["to my ", "to the ", "to ", "my ", "the ", "moja ", "moj ", "moje "] {
            if key.hasPrefix(prefix) {
                key = String(key.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        switch key {
        case "dom", "domu", "domem", "home", "house": return "Home"
        case "praca", "pracy", "prace", "work", "office": return "Work"
        case "szkola", "szkoly", "szkole", "school": return "School"
        case "silownia", "silownie", "gym", "fitness": return "Gym"
        default: return nil
        }
    }

    private static func looksPrimarilyEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let asciiLetters = letters.filter { $0.isASCII }
        // Brak typowych PL znaków i większość liter ASCII → traktuj jako EN.
        let hasPolish = text.range(of: #"[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]"#, options: .regularExpression) != nil
        return !hasPolish && Double(asciiLetters.count) / Double(letters.count) > 0.9
    }
}
