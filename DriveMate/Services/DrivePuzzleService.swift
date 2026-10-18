import Foundation

/// Kreatywne łamigówki — generowanie i ocena przez model deterministyczny (wiele kluczy),
/// z opcjonalnym wsparciem Foundation Models tylko gdy polityka na to pozwala.
@MainActor
final class DrivePuzzleService {
    static let shared = DrivePuzzleService()

    enum Category: String, CaseIterable {
        case math
        case fantasy
        case science
        case philosophy

        var spoken: String {
            switch self {
            case .math: return "matematyczna"
            case .fantasy: return "fantasy"
            case .science: return "naukowa"
            case .philosophy: return "filozoficzna"
            }
        }
    }

    struct Puzzle: Identifiable {
        let id: UUID
        let category: Category
        let prompt: String
        let goodThemes: [String]
        let badThemes: [String]
        let numericAnswer: Double?
        let numericTolerance: Double
        let acceptHint: String
        let rejectHint: String
    }

    enum Judge {
        case accept(String)
        case reject(String)
        case partial(String)
    }

    private(set) var pending: Puzzle?
    /// Ostatnia zadana zagadka — do „powtórz zagadkę” (nawet po odpowiedzi).
    private(set) var lastPuzzle: Puzzle?

    private init() {}

    var isAwaitingAnswer: Bool { pending != nil }

    var hasPuzzleToRepeat: Bool { lastPuzzle != nil || pending != nil }

    func clear() { pending = nil }

    /// Losowa łamigówka — zawsze z modelu deterministycznego (szablony + banki słów).
    func pose(category: Category? = nil) -> String {
        let pick = DeterministicBrainEngine.shared.makePuzzlePayload(categoryRaw: category?.rawValue)
        pending = pick
        lastPuzzle = pick
        presentPuzzleCard(pick)
        return spokenPresentation(for: pick, prefix: nil)
    }

    /// Powtórz ostatnią zagadkę (głos + kafelek do końca TTS) i wznów oczekiwanie na odpowiedź.
    func repeatLast() -> String? {
        guard let pick = lastPuzzle ?? pending else { return nil }
        pending = pick
        presentPuzzleCard(pick)
        return spokenPresentation(for: pick, prefix: "Powtarzam.")
    }

    /// Jedna przykładowa / opcjonalna odpowiedź do przeczytania przy „nie wiem”.
    func sampleAnswerSpoken(for puzzle: Puzzle) -> String {
        if let expected = puzzle.numericAnswer {
            return "Opcjonalna odpowiedź to \(Self.formatNumber(expected)). \(puzzle.acceptHint)"
        }
        return "Opcjonalna odpowiedź: \(puzzle.acceptHint)"
    }

    private func presentPuzzleCard(_ puzzle: Puzzle) {
        DriveInfoCardStore.shared.present(
            .puzzle(category: puzzle.category.spoken, prompt: puzzle.prompt)
        )
    }

    private func spokenPresentation(for puzzle: Puzzle, prefix: String?) -> String {
        let head = prefix.map { "\($0) " } ?? ""
        return "\(head)Łamigówka \(puzzle.category.spoken). \(puzzle.prompt) Powiedz swoją odpowiedź — nie ma jednego klucza, ale ma mieć sens."
    }

    func judgeAnswer(_ raw: String) async -> Judge? {
        guard let puzzle = pending else { return nil }
        let fold = DriveIntentQueryHelpers.foldForMatching(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard fold.count >= 2 else {
            return .partial("Powiedz pełniejszą odpowiedź — jednym słowem czasem trudno ocenić.")
        }

        // „Nie wiem” / prośba o podpowiedź → podaj opcjonalną odpowiedź.
        let dontKnow = [
            "nie wiem", "bez pojecia", "nie mam pojecia", "nie mam pojęcia",
            "podpowiedz", "podpowiedz mi", "jaka odpowiedz", "jaka jest odpowiedz",
            "daj odpowiedz", "powiedz odpowiedz", "daj podpowiedz", "hint",
            "nie znam odpowiedzi", "nie umiem", "help"
        ]
        if dontKnow.contains(where: { fold.contains($0) }) {
            let sample = sampleAnswerSpoken(for: puzzle)
            pending = nil
            return .partial("OK. \(sample) Jak chcesz, poproś o kolejną łamigówkę albo powiedz „powtórz zagadkę”.")
        }

        let escape = ["odpuszczam", "nastepne", "poddaje", "poddaję", "odpusc", "pomin", "pomiń"]
        if escape.contains(where: { fold.contains($0) }) {
            pending = nil
            return .partial("OK — odpuszczamy. Jak chcesz, poproś o kolejną łamigówkę.")
        }

        // Prośba o nową / powtórzenie zagadki — obsłużona wyżej w VoiceCommandProcessor.
        if fold.contains("lamig") || fold.contains("zagadk") || fold.contains("puzzle")
            || fold.contains("powtorz") {
            return nil
        }

        // Matematyka z liczbą — twardy check.
        if let expected = puzzle.numericAnswer {
            if let value = Self.extractNumber(from: fold) {
                pending = nil
                if abs(value - expected) <= puzzle.numericTolerance {
                    return .accept(puzzle.acceptHint)
                }
                return .reject("Hmm, liczę inaczej — bliżej \(Self.formatNumber(expected)). \(puzzle.rejectHint)")
            }
            let goodHit = puzzle.goodThemes.contains { fold.contains($0) }
            if goodHit {
                return .partial("Kierunek dobry — podaj jeszcze konkretną liczbę albo wynik.")
            }
        }

        // Model deterministyczny: wiele kluczy + synonimy + scoring klastrów.
        let det = DeterministicBrainEngine.shared.judgeOpenAnswer(
            fold: fold,
            acceptKeys: puzzle.goodThemes,
            rejectKeys: puzzle.badThemes,
            acceptHint: puzzle.acceptHint,
            rejectHint: puzzle.rejectHint
        )
        switch det {
        case .accept, .reject:
            pending = nil
            return det
        case .partial:
            break
        }

        // Foundation Models — tylko gdy użytkownik / sprzęt na to pozwala.
        if AssistantModelPolicy.usesFoundationModels,
           #available(iOS 26.0, *),
           let chat = CoreLM.makeChatSession() {
            let prompt = """
            Oceń odpowiedź kierowcy na łamigówkę. Odpowiedź NIE musi być jedyną poprawną —
            ma być sensowna, realistyczna w świecie zagadki i nie obchodzić reguł absurdem.

            Zagadka (\(puzzle.category.spoken)): \(puzzle.prompt)

            Odpowiedź kierowcy: \(raw)

            Kryteria ODRZUCENIA: nierealne jak na kontekst (np. żaba buduje most z patyków),
            siłowe ominięcie zagadki, magia „bo tak”, sprzeczność z fizyką/logiką zagadki.
            Kryteria AKCEPTACJI: kreatywne, ale wiarygodne w świecie zagadki.

            Odpowiedz TYLKO w formacie:
            WERDYKT: OK | NIE | CZĘŚCIOWO
            KOMENTARZ: jedno krótkie zdanie po polsku do przeczytania na głos.
            """
            if let text = try? await CoreLM.honestReply(to: prompt, session: chat) {
                let upper = text.uppercased()
                let comment = Self.extractComment(from: text) ?? puzzle.acceptHint
                pending = nil
                if upper.contains("WERDYKT: OK") || (upper.contains("OK") && !upper.contains("NIE")) {
                    return .accept(comment)
                }
                if upper.contains("CZĘŚCIOWO") || upper.contains("CZESCIOWO") {
                    return .partial(comment)
                }
                return .reject(comment.isEmpty ? puzzle.rejectHint : comment)
            }
        }

        pending = nil
        if case .partial(let msg) = det { return .partial(msg) }
        return det
    }

    static func category(fromFolded lower: String) -> Category? {
        if lower.contains("matemat") || lower.contains("liczb") || lower.contains("rachunk") { return .math }
        if lower.contains("fantasy") || lower.contains("fantaz") || lower.contains("smok")
            || lower.contains("magicz") || lower.contains("bajk") { return .fantasy }
        if lower.contains("nauk") || lower.contains("fizyk") || lower.contains("chemic")
            || lower.contains("biolog") || lower.contains("kosmos") { return .science }
        if lower.contains("filozof") || lower.contains("myslen") || lower.contains("etycz") { return .philosophy }
        return nil
    }

    private static func extractComment(from text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let fold = line.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
                .lowercased()
            if fold.hasPrefix("komentarz:") {
                let raw = line.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
    }

    private static func extractNumber(from fold: String) -> Double? {
        let words: [String: Double] = [
            "zero": 0, "jeden": 1, "jedna": 1, "dwa": 2, "dwie": 2, "trzy": 3,
            "cztery": 4, "piec": 5, "pięć": 5, "szesc": 6, "siedem": 7,
            "osiem": 8, "dziewiec": 9, "dziesiec": 10, "jedenascie": 11,
            "dwanascie": 12, "pietnascie": 15, "dwadziescia": 20,
            "trzydziesci": 30, "czterdziesci": 40, "piecdziesiat": 50,
            "szescdziesiat": 60
        ]
        for (w, v) in words where fold.contains(w) { return v }
        let pattern = #/-?\d+[.,]?\d*/#
        if let match = fold.firstMatch(of: pattern) {
            let s = String(match.0).replacingOccurrences(of: ",", with: ".")
            return Double(s)
        }
        return nil
    }

    private static func formatNumber(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}
