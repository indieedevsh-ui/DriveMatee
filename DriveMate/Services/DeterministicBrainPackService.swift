import Foundation
import Combine

/// Pobieranie / instalacja offline paczki modelu deterministycznego (słowniki, szablony, klucze).
@MainActor
final class DeterministicBrainPackService: ObservableObject {
    static let shared = DeterministicBrainPackService()

    enum Phase: Equatable {
        case idle
        case downloading
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressPercent: Int = 0
    @Published private(set) var statusLine: String = ""
    @Published private(set) var packSummary: String?

    private var installTask: Task<Void, Never>?

    private var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DeterministicBrain", isDirectory: true)
    }

    private var packURL: URL { rootURL.appendingPathComponent("brain.pack.json") }
    private var markerURL: URL { rootURL.appendingPathComponent("installed.marker") }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
            && FileManager.default.fileExists(atPath: packURL.path)
    }

    var isActive: Bool {
        if case .downloading = phase { return true }
        return false
    }

    private init() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        refreshSummary()
    }

    func refreshSummary() {
        if isInstalled {
            phase = .completed
            progress = 1
            progressPercent = 100
            if let data = try? Data(contentsOf: packURL),
               let pack = try? JSONDecoder().decode(DeterministicBrainPackBuilder.Pack.self, from: data) {
                packSummary = "v\(pack.version) · \(pack.synonymClusters.count) klastrów · \(pack.puzzleSeeds.count) szablonów · \(pack.trivia.count) ciekawostek"
                statusLine = "Model deterministyczny zainstalowany — działa offline."
            } else if let data = try? Data(contentsOf: packURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let version = json["version"] as? Int ?? 1
                let clusters = (json["synonymClusters"] as? [String: Any])?.count ?? 0
                let seeds = (json["puzzleSeeds"] as? [Any])?.count ?? 0
                let trivia = (json["trivia"] as? [Any])?.count ?? 0
                packSummary = "v\(version) · \(clusters) klastrów · \(seeds) szablonów · \(trivia) ciekawostek"
                statusLine = "Model deterministyczny zainstalowany — działa offline."
            } else {
                packSummary = "Paczka zainstalowana"
                statusLine = "Model deterministyczny gotowy."
            }
        } else {
            if case .downloading = phase { return }
            phase = .idle
            progress = 0
            progressPercent = 0
            packSummary = nil
            statusLine = "Pobierz model deterministyczny, żeby łamigówki, ciekawostki i odpowiedzi offline działały w pełni."
        }
    }

    /// Instalacja offline z wbudowanego generatora (bez sieci).
    func downloadAndInstall() {
        guard !isActive else { return }
        installTask?.cancel()
        phase = .downloading
        progress = 0
        progressPercent = 0
        statusLine = "Przygotowuję słowniki i szablony…"
        packSummary = nil

        installTask = Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                let steps = 12
                for step in 1...steps {
                    guard !Task.isCancelled else { return }
                    try await Task.sleep(nanoseconds: 120_000_000)
                    progress = Double(step) / Double(steps)
                    progressPercent = Int((progress * 100).rounded())
                    statusLine = Self.status(for: step)
                }

                let data = try DeterministicBrainPackBuilder.encodeFullPack()
                try data.write(to: packURL, options: .atomic)
                try "ok".data(using: .utf8)?.write(to: markerURL, options: .atomic)

                UserDefaults.standard.set(true, forKey: AssistantModelPolicy.packInstalledKey)
                phase = .completed
                progress = 1
                progressPercent = 100
                refreshSummary()
                NotificationCenter.default.post(name: .deterministicBrainPackDidChange, object: nil)
            } catch {
                phase = .failed(error.localizedDescription)
                statusLine = "Nie udało się zainstalować: \(error.localizedDescription)"
            }
        }
    }

    func deletePack() {
        installTask?.cancel()
        try? FileManager.default.removeItem(at: packURL)
        try? FileManager.default.removeItem(at: markerURL)
        UserDefaults.standard.set(false, forKey: AssistantModelPolicy.packInstalledKey)
        phase = .idle
        progress = 0
        progressPercent = 0
        refreshSummary()
        NotificationCenter.default.post(name: .deterministicBrainPackDidChange, object: nil)
    }

    func loadPackData() -> Data? {
        guard isInstalled else { return nil }
        return try? Data(contentsOf: packURL)
    }

    private static func status(for step: Int) -> String {
        switch step {
        case 1: return "Buduję klastry synonimów…"
        case 2: return "Rozszerzam klucze odpowiedzi…"
        case 3: return "Generuję bank słów fantasy…"
        case 4: return "Generuję bank słów naukowych…"
        case 5: return "Składam szablony łamigówek…"
        case 6: return "Składam warianty matematyczne…"
        case 7: return "Składam zagadki filozoficzne…"
        case 8: return "Pakuję ciekawostki…"
        case 9: return "Buduję szablony narracji ulic…"
        case 10: return "Indeksuję frazy rozmowy…"
        case 11: return "Kompresuję paczkę offline…"
        default: return "Zapisuję model deterministyczny…"
        }
    }
}
