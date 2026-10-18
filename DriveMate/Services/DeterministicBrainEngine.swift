import Foundation

/// Zaawansowany model deterministyczny offline: synonimy, szablony, wiele kluczy odpowiedzi.
@MainActor
final class DeterministicBrainEngine {
    static let shared = DeterministicBrainEngine()

    typealias Pack = DeterministicBrainPackBuilder.Pack
    typealias PuzzleSeed = DeterministicBrainPackBuilder.PuzzleSeed
    typealias ChatRule = DeterministicBrainPackBuilder.ChatRule

    private var pack: Pack
    private var recentPuzzleIDs: [String] = []
    private let maxRecent = 10

    private init() {
        pack = DeterministicBrainPackBuilder.seedPack()
        reloadFromDisk()
        NotificationCenter.default.addObserver(
            forName: .deterministicBrainPackDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
    }

    var isReady: Bool {
        DeterministicBrainPackService.shared.isInstalled || pack.version >= 1
    }

    var synonymClusterCount: Int { pack.synonymClusters.count }
    var triviaCount: Int { pack.trivia.count }
    var puzzleSeedCount: Int { pack.puzzleSeeds.count }

    func reloadFromDisk() {
        if let data = DeterministicBrainPackService.shared.loadPackData(),
           let decoded = try? JSONDecoder().decode(Pack.self, from: data) {
            pack = decoded
        } else {
            pack = DeterministicBrainPackBuilder.seedPack()
        }
    }


    // MARK: - Puzzles

    func posePuzzle(categoryRaw: String?) -> (id: String, categorySpoken: String, prompt: String, acceptHint: String) {
        let seeds = pack.puzzleSeeds.filter { categoryRaw == nil || $0.category == categoryRaw }
        let fresh = seeds.filter { !recentPuzzleIDs.contains($0.id) }
        var pick = (fresh.isEmpty ? seeds : fresh).randomElement() ?? pack.puzzleSeeds[0]
        pick = materialize(pick)

        recentPuzzleIDs.append(pick.id)
        if recentPuzzleIDs.count > maxRecent {
            recentPuzzleIDs.removeFirst(recentPuzzleIDs.count - maxRecent)
        }

        let spoken = categorySpoken(pick.category)
        let text = "Łamigówka \(spoken). \(pick.prompt) Powiedz swoją odpowiedź — nie ma jednego klucza, ale ma mieć sens."
        return (pick.id, spoken, text, pick.acceptHint)
    }

    func makePuzzlePayload(categoryRaw: String?) -> DrivePuzzleService.Puzzle {
        let seeds = pack.puzzleSeeds.filter { categoryRaw == nil || $0.category == categoryRaw }
        let fresh = seeds.filter { !recentPuzzleIDs.contains($0.id) }
        var pick = (fresh.isEmpty ? seeds : fresh).randomElement() ?? pack.puzzleSeeds[0]
        pick = materialize(pick)
        recentPuzzleIDs.append(pick.id)
        if recentPuzzleIDs.count > maxRecent {
            recentPuzzleIDs.removeFirst(recentPuzzleIDs.count - maxRecent)
        }

        let cat = DrivePuzzleService.Category(rawValue: pick.category) ?? .fantasy
        let accept = expandKeys(pick.acceptKeys, using: pack.acceptExpansions)
        let reject = expandKeys(pick.rejectKeys, using: pack.rejectExpansions)
        return DrivePuzzleService.Puzzle(
            id: UUID(),
            category: cat,
            prompt: pick.prompt,
            goodThemes: accept,
            badThemes: reject,
            numericAnswer: pick.numericAnswer,
            numericTolerance: pick.numericTolerance,
            acceptHint: pick.acceptHint,
            rejectHint: pick.rejectHint
        )
    }

    /// Ocena odpowiedzi wieloma kluczami (synonimy + klastry) — bez AI.
    func judgeOpenAnswer(
        fold: String,
        acceptKeys: [String],
        rejectKeys: [String],
        acceptHint: String,
        rejectHint: String
    ) -> DrivePuzzleService.Judge {
        let expandedReject = expandKeys(rejectKeys, using: pack.rejectExpansions)
        if expandedReject.contains(where: { fold.contains($0) }) {
            return .reject(rejectHint)
        }

        let expandedAccept = expandKeys(acceptKeys, using: pack.acceptExpansions)
        let hits = expandedAccept.filter { fold.contains($0) }.count
        if hits >= 1 {
            return .accept(acceptHint)
        }

        // Fuzzy: token overlap z klastrami synonimów powiązanymi z acceptKeys
        let score = clusterScore(fold: fold, seeds: acceptKeys)
        if score >= 0.34 {
            return .accept(acceptHint)
        }
        if score >= 0.18, fold.count >= 14 {
            return .partial("Kierunek ciekawy — \(acceptHint)")
        }
        if fold.count >= 22 {
            return .partial("Ciekawe podejście. \(acceptHint)")
        }
        return .reject(rejectHint)
    }

    // MARK: - Trivia

    func nextTrivia(excluding used: Set<Int>) -> (index: Int, text: String)? {
        guard !pack.trivia.isEmpty else { return nil }
        let available = pack.trivia.indices.filter { !used.contains($0) }
        let pool = available.isEmpty ? Array(pack.trivia.indices) : available
        guard let idx = pool.randomElement() else { return nil }
        return (idx, pack.trivia[idx])
    }

    var allTrivia: [String] { pack.trivia }

    // MARK: - Street history (bez AI)

    func narrateStreetHistory(place: String, wiki: String?, district: String?) -> String {
        if let wiki, !wiki.isEmpty {
            let prefix = pack.streetHistoryTemplates.randomElement()
                ?? "Oto co wiem o historii tego miejsca:"
            let short = wiki.count > 320 ? String(wiki.prefix(300)) + "…" : wiki
            return "\(place). \(prefix) \(short)"
        }
        let districtBit = (district?.isEmpty == false) ? " w okolicy \(district!)" : ""
        let templates = [
            "\(place)\(districtBit). Nie mam pewnego wpisu historycznego offline — nazwa bywa związana z patronem, dawną funkcją drogi albo lokalną tradycją.",
            "\(place)\(districtBit). W Polsce wiele ulic nosi imiona postaci lub wydarzeń; bez źródła nie zmyślam dat. Mogę opowiedzieć więcej, gdy będzie dostęp do Wikipedii.",
            "\(place)\(districtBit). Historycznie takie ulice często powstawały przy rozbudowie dzielnicy albo przy dawnym trakcie. Nie mam tu pewnej daty założenia."
        ]
        return templates.randomElement() ?? templates[0]
    }

    // MARK: - Chat / assistant replies

    func replyToChat(_ transcript: String) -> String? {
        let fold = DriveIntentQueryHelpers.foldForMatching(transcript)
        guard fold.count >= 2 else { return nil }

        for rule in pack.chatReplies {
            if rule.anyOf.contains(where: { fold.contains($0) }) {
                return rule.replies.randomElement()
            }
        }

        // Ogólne pytania „co myślisz / opowiedz” — filler z banku
        if fold.contains("opowiedz") || fold.contains("co myslisz") || fold.contains("pogadaj")
            || fold.contains("nudze") || fold.contains("nudzę") {
            return pack.fillerReplies.randomElement()
        }
        return nil
    }

    // MARK: - Helpers

    private func materialize(_ seed: PuzzleSeed) -> PuzzleSeed {
        guard let template = seed.promptTemplate, !template.isEmpty else { return seed }
        var text = template
        var out = seed
        var filled: [String: String] = [:]

        func fill(slot: String, bankName: String) {
            guard text.contains("{\(slot)}") else { return }
            let word = pack.wordBanks[bankName]?.randomElement() ?? slot
            text = text.replacingOccurrences(of: "{\(slot)}", with: word)
            filled[slot] = word
            let fold = DriveIntentQueryHelpers.foldForMatching(word)
            out.acceptKeys.append(fold)
            if fold.count > 4 { out.acceptKeys.append(String(fold.prefix(4))) }
        }

        if let banks = seed.slotBanks {
            for (slot, bankName) in banks { fill(slot: slot, bankName: bankName) }
        }
        for (name, _) in pack.wordBanks {
            fill(slot: name, bankName: name)
        }

        // „N latarni → N-1 luk”
        if let a = filled["numberA"], let n = Int(a), n > 1 {
            out.numericAnswer = Double(n - 1)
            out.numericTolerance = 0.1
            out.acceptKeys.append(contentsOf: [String(n - 1), numberWord(n - 1)].compactMap { $0 })
        }

        out.prompt = text
        out.id = "\(seed.id)-\(abs(text.hashValue))"
        return out
    }

    private func numberWord(_ n: Int) -> String? {
        let map = [2: "dwa", 3: "trzy", 4: "cztery", 5: "piec", 6: "szesc", 7: "siedem"]
        return map[n]
    }

    private func expandKeys(_ keys: [String], using map: [String: [String]]) -> [String] {
        var result: [String] = []
        for key in keys {
            let fold = DriveIntentQueryHelpers.foldForMatching(key)
            result.append(fold)
            if let extra = map[fold] {
                result.append(contentsOf: extra.map { DriveIntentQueryHelpers.foldForMatching($0) })
            }
            if let cluster = pack.synonymClusters[fold] {
                result.append(contentsOf: cluster.map { DriveIntentQueryHelpers.foldForMatching($0) })
            }
        }
        return Array(Set(result)).filter { !$0.isEmpty }
    }

    private func clusterScore(fold: String, seeds: [String]) -> Double {
        var best = 0.0
        let tokens = fold.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        guard !tokens.isEmpty else { return 0 }
        for seed in seeds {
            let seedFold = DriveIntentQueryHelpers.foldForMatching(seed)
            var related = Set(expandKeys([seedFold], using: pack.acceptExpansions))
            if let cluster = pack.synonymClusters[seedFold] {
                related.formUnion(cluster.map { DriveIntentQueryHelpers.foldForMatching($0) })
            }
            let hits = tokens.filter { token in related.contains(where: { $0.contains(token) || token.contains($0) }) }.count
            best = max(best, Double(hits) / Double(tokens.count))
        }
        return best
    }

    private func categorySpoken(_ raw: String) -> String {
        switch raw {
        case "math": return "matematyczna"
        case "fantasy": return "fantasy"
        case "science": return "naukowa"
        case "philosophy": return "filozoficzna"
        default: return raw
        }
    }
}
