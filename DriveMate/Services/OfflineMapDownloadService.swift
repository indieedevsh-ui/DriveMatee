import Foundation
import CoreLocation
import Combine
import Network
import MapKit

/// Paczka kafelków mapy (OSM) do użytku offline — z wznawianiem po utracie sieci.
@MainActor
final class OfflineMapDownloadService: ObservableObject {
    static let shared = OfflineMapDownloadService()

    enum Phase: Equatable {
        case idle
        case downloading
        case pausedOffline
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressPercent: Int = 0
    @Published private(set) var statusLine: String = ""
    @Published private(set) var packSummary: String?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "DriveMate.OfflineMap.Net")
    private var downloadTask: Task<Void, Never>?
    private var pathSatisfied = true

    private var centerLat: Double = 0
    private var centerLon: Double = 0
    private var radiusMeters: CLLocationDistance = 10_000
    private var pendingTiles: [TileKey] = []
    private var completedKeys: Set<String> = []
    private var totalCount = 0

    private let minZoom = 12
    private let maxZoom = 15
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "DriveMate/1.0 (iOS; offline map cache; contact@drivemate.local)"
        ]
        return URLSession(configuration: config)
    }()

    private struct TileKey: Hashable, Codable {
        let z: Int
        let x: Int
        let y: Int
        var id: String { "\(z)/\(x)/\(y)" }
    }

    private struct Manifest: Codable {
        var centerLat: Double
        var centerLon: Double
        var radiusMeters: Double
        var completed: [String]
        var total: Int
        var finished: Bool
    }

    private var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("OfflineMaps", isDirectory: true)
    }

    private var manifestURL: URL { rootURL.appendingPathComponent("manifest.json") }

    var isActive: Bool {
        switch phase {
        case .downloading, .pausedOffline: return true
        default: return false
        }
    }

    var showsDriveBadge: Bool {
        switch phase {
        case .downloading, .pausedOffline: return true
        default: return false
        }
    }

    private init() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        loadManifestIfNeeded()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePath(path.status == .satisfied)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Start nowego pobierania (lub wznów istniejące dla tego samego obszaru).
    func startDownload(center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) {
        downloadTask?.cancel()
        self.centerLat = center.latitude
        self.centerLon = center.longitude
        self.radiusMeters = radiusMeters

        if let existing = readManifest(),
           abs(existing.centerLat - center.latitude) < 0.002,
           abs(existing.centerLon - center.longitude) < 0.002,
           abs(existing.radiusMeters - radiusMeters) < 50,
           !existing.finished {
            completedKeys = Set(existing.completed)
            totalCount = max(existing.total, 1)
        } else {
            completedKeys = []
            pendingTiles = Self.buildTileList(
                center: center,
                radiusMeters: radiusMeters,
                minZoom: minZoom,
                maxZoom: maxZoom
            )
            totalCount = pendingTiles.count
            persistManifest(finished: false)
        }

        if pendingTiles.isEmpty {
            pendingTiles = Self.buildTileList(
                center: center,
                radiusMeters: radiusMeters,
                minZoom: minZoom,
                maxZoom: maxZoom
            )
            totalCount = pendingTiles.count
        }
        // Odrzuć już pobrane.
        pendingTiles.removeAll { completedKeys.contains($0.id) }
        refreshProgress()
        phase = .downloading
        statusLine = "Pobieranie map offline…"
        packSummary = String(format: "Obszar %.0f km · %d/%d kafelków", radiusMeters / 1000, completedKeys.count, totalCount)
        resumeLoop()
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        phase = .idle
        statusLine = "Anulowano."
        progress = 0
        progressPercent = 0
    }

    func deletePack() {
        cancel()
        try? FileManager.default.removeItem(at: rootURL)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        completedKeys = []
        pendingTiles = []
        totalCount = 0
        packSummary = nil
        phase = .idle
        statusLine = "Usunięto mapy offline."
        progress = 0
        progressPercent = 0
    }

    // MARK: - Loop

    private func handlePath(_ online: Bool) {
        let was = pathSatisfied
        pathSatisfied = online
        guard online != was else { return }
        if online {
            if phase == .pausedOffline || (phase == .downloading && downloadTask == nil) {
                phase = .downloading
                statusLine = "Internet wrócił — wznawiam pobieranie…"
                resumeLoop()
            }
        } else if phase == .downloading {
            phase = .pausedOffline
            statusLine = "Brak sieci — wstrzymano. Wznawiam od miejsca przerwania."
            downloadTask?.cancel()
            downloadTask = nil
            persistManifest(finished: false)
        }
    }

    private func resumeLoop() {
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            await self?.runDownload()
        }
    }

    private func runDownload() async {
        while !Task.isCancelled {
            guard pathSatisfied else {
                phase = .pausedOffline
                persistManifest(finished: false)
                return
            }
            guard let tile = pendingTiles.first else {
                phase = .completed
                progress = 1
                progressPercent = 100
                statusLine = "Mapy offline gotowe."
                packSummary = String(format: "Obszar %.0f km · %d kafelków", radiusMeters / 1000, completedKeys.count)
                persistManifest(finished: true)
                return
            }
            do {
                try await downloadTile(tile)
                pendingTiles.removeFirst()
                completedKeys.insert(tile.id)
                refreshProgress()
                if completedKeys.count % 8 == 0 {
                    persistManifest(finished: false)
                }
            } catch {
                if !pathSatisfied {
                    phase = .pausedOffline
                    statusLine = "Brak sieci — wstrzymano. Wznawiam od miejsca przerwania."
                    persistManifest(finished: false)
                    return
                }
                // Pojedynczy błąd kafelka — pomiń i idź dalej (nie od zera).
                pendingTiles.removeFirst()
                completedKeys.insert(tile.id)
                refreshProgress()
            }
        }
    }

    private func downloadTile(_ tile: TileKey) async throws {
        let fileURL = rootURL.appendingPathComponent("\(tile.z)/\(tile.x)/\(tile.y).png")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let url = URL(string: "https://tile.openstreetmap.org/\(tile.z)/\(tile.x)/\(tile.y).png")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func refreshProgress() {
        let done = completedKeys.count
        let total = max(totalCount, 1)
        progress = min(1, Double(done) / Double(total))
        progressPercent = Int((progress * 100).rounded())
        packSummary = String(format: "Obszar %.0f km · %d/%d", radiusMeters / 1000, done, total)
        if phase == .downloading {
            statusLine = "Pobieranie map offline… \(progressPercent)%"
        }
    }

    private func persistManifest(finished: Bool) {
        let m = Manifest(
            centerLat: centerLat,
            centerLon: centerLon,
            radiusMeters: radiusMeters,
            completed: Array(completedKeys),
            total: totalCount,
            finished: finished
        )
        if let data = try? JSONEncoder().encode(m) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private func readManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func loadManifestIfNeeded() {
        guard let m = readManifest() else { return }
        centerLat = m.centerLat
        centerLon = m.centerLon
        radiusMeters = m.radiusMeters
        completedKeys = Set(m.completed)
        totalCount = max(m.total, completedKeys.count)
        refreshProgress()
        if m.finished {
            phase = .completed
            statusLine = "Mapy offline gotowe."
            packSummary = String(format: "Obszar %.0f km · %d kafelków", radiusMeters / 1000, completedKeys.count)
        } else if !completedKeys.isEmpty {
            phase = .pausedOffline
            statusLine = "Pobieranie wstrzymane — wznów z ustawień lub komendą głosową."
            pendingTiles = Self.buildTileList(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                radiusMeters: radiusMeters,
                minZoom: minZoom,
                maxZoom: maxZoom
            ).filter { !completedKeys.contains($0.id) }
        }
    }

    /// Wznów niedokończone pobieranie (np. z ustawień).
    func resumeIfNeeded() {
        guard phase == .pausedOffline || (phase != .completed && !completedKeys.isEmpty && progress < 1) else { return }
        if pendingTiles.isEmpty {
            pendingTiles = Self.buildTileList(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                radiusMeters: radiusMeters,
                minZoom: minZoom,
                maxZoom: maxZoom
            ).filter { !completedKeys.contains($0.id) }
        }
        phase = .downloading
        resumeLoop()
    }

    // MARK: - Tile math

    private static func buildTileList(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        minZoom: Int,
        maxZoom: Int
    ) -> [TileKey] {
        let latDelta = radiusMeters / 111_320
        let lonDelta = radiusMeters / (111_320 * max(0.2, cos(center.latitude * .pi / 180)))
        let south = center.latitude - latDelta
        let north = center.latitude + latDelta
        let west = center.longitude - lonDelta
        let east = center.longitude + lonDelta
        var tiles: [TileKey] = []
        for z in minZoom...maxZoom {
            let x0 = lonToTileX(west, zoom: z)
            let x1 = lonToTileX(east, zoom: z)
            let y0 = latToTileY(north, zoom: z)
            let y1 = latToTileY(south, zoom: z)
            for x in min(x0, x1)...max(x0, x1) {
                for y in min(y0, y1)...max(y0, y1) {
                    tiles.append(TileKey(z: z, x: x, y: y))
                }
            }
        }
        return tiles
    }

    private static func lonToTileX(_ lon: Double, zoom: Int) -> Int {
        Int(floor((lon + 180) / 360 * pow(2, Double(zoom))))
    }

    private static func latToTileY(_ lat: Double, zoom: Int) -> Int {
        let latRad = lat * .pi / 180
        let n = pow(2, Double(zoom))
        return Int(floor((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n))
    }
}

/// Store okienka wyboru obszaru mapy offline.
@MainActor
final class OfflineMapPromptStore: ObservableObject {
    static let shared = OfflineMapPromptStore()

    @Published var isPresented = false
    @Published var center: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 52.23, longitude: 21.01)
    @Published var radiusMeters: CLLocationDistance = 10_000

    func present(around coordinate: CLLocationCoordinate2D?) {
        if let coordinate {
            center = coordinate
        } else if let gps = MapKitNavigationService.shared.location?.coordinate {
            center = gps
        }
        radiusMeters = 10_000
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    func confirm() {
        OfflineMapDownloadService.shared.startDownload(center: center, radiusMeters: radiusMeters)
        isPresented = false
    }
}
