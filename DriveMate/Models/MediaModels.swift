import Foundation

struct MusicTrack: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var fileName: String
    var createdAt: Date

    var fileURL: URL {
        MusicLibraryService.musicDirectory.appendingPathComponent(fileName)
    }
}

struct RecordedClip: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var fileName: String
    var createdAt: Date
    var durationSeconds: Double

    var fileURL: URL {
        ClipStorageService.clipsDirectory.appendingPathComponent(fileName)
    }

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return "Klip \(formatter.string(from: createdAt))"
    }
}
