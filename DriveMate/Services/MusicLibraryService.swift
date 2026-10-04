import Foundation
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class MusicLibraryService: ObservableObject {
    static let shared = MusicLibraryService()

    static let musicDirectory: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private let indexURL = musicDirectory.appendingPathComponent("library.json")

    @Published private(set) var tracks: [MusicTrack] = []
    @Published var isImporting = false
    @Published var importMessage: String?

    private init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([MusicTrack].self, from: data) else {
            tracks = []
            return
        }
        tracks = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        persist()
    }

    func importFiles(from urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            do {
                let track = try await importSingle(url: url)
                tracks.append(track)
                imported += 1
            } catch {
                importMessage = error.localizedDescription
            }
        }

        persist()
        if imported > 0 {
            importMessage = "Zaimportowano \(imported) plik(ów)."
        }
    }

    func delete(_ track: MusicTrack) {
        try? FileManager.default.removeItem(at: track.fileURL)
        tracks.removeAll { $0.id == track.id }
        persist()
    }

    private func importSingle(url: URL) async throws -> MusicTrack {
        let ext = url.pathExtension.lowercased()
        let id = UUID()
        let baseName = url.deletingPathExtension().lastPathComponent

        switch ext {
        case "mp3":
            let fileName = "\(id.uuidString).mp3"
            let dest = Self.musicDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return MusicTrack(id: id, name: baseName, fileName: fileName, createdAt: .now)

        case "mp4", "m4v", "mov":
            // iOS nie udostępnia licencjonowanego enkodera MP3 — wyodrębniamy audio do AAC (.m4a),
            // które jest legalnym, natywnym formatem Apple i działa w odtwarzaczu tak samo.
            let fileName = "\(id.uuidString).m4a"
            let dest = Self.musicDirectory.appendingPathComponent(fileName)
            try await extractAudio(from: url, to: dest)
            return MusicTrack(id: id, name: baseName, fileName: fileName, createdAt: .now)

        case "m4a", "aac":
            let fileName = "\(id.uuidString).\(ext)"
            let dest = Self.musicDirectory.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: url, to: dest)
            return MusicTrack(id: id, name: baseName, fileName: fileName, createdAt: .now)

        default:
            throw MusicImportError.unsupportedType
        }
    }

    private func extractAudio(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MusicImportError.conversionFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try await session.export(to: destination, as: .m4a)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

enum MusicImportError: LocalizedError {
    case unsupportedType
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "Nieobsługiwany format. Użyj MP3 lub MP4."
        case .conversionFailed:
            "Nie udało się wyodrębnić audio z pliku wideo."
        }
    }
}
