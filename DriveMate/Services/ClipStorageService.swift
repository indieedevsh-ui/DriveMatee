import Foundation
import Combine

@MainActor
final class ClipStorageService: ObservableObject {
    static let clipsDirectory: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private let indexURL = clipsDirectory.appendingPathComponent("clips.json")

    @Published private(set) var clips: [RecordedClip] = []

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([RecordedClip].self, from: data) else {
            clips = []
            return
        }
        clips = decoded
            .filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
            .sorted { $0.createdAt > $1.createdAt }
        persist()
    }

    func addClip(at tempURL: URL, durationSeconds: Double = 10) {
        let id = UUID()
        let fileName = "\(id.uuidString).mp4"
        let dest = Self.clipsDirectory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            let clip = RecordedClip(
                id: id,
                fileName: fileName,
                createdAt: .now,
                durationSeconds: durationSeconds
            )
            clips.insert(clip, at: 0)
            persist()
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    func delete(_ clip: RecordedClip) {
        try? FileManager.default.removeItem(at: clip.fileURL)
        clips.removeAll { $0.id == clip.id }
        persist()
    }

    func deleteAll() {
        for clip in clips {
            try? FileManager.default.removeItem(at: clip.fileURL)
        }
        clips.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(clips) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
