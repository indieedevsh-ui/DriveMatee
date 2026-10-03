import Foundation
import MapKit
import UIKit
import CoreLocation

/// Realistyczny podgląd miejsca z Apple Maps (Look Around gdy dostępne, inaczej mapa).
/// Uwaga: `MKMapSnapshotter.Options.traitCollection` potrafi wywołać „hit program assert” — nie ustawiamy.
@MainActor
enum AppleMapsPlaceVisuals {
    static func placePhoto(
        at coordinate: CLLocationCoordinate2D,
        size: CGSize = CGSize(width: 640, height: 320)
    ) async -> UIImage? {
        let safe = CGSize(
            width: max(64, min(size.width, 800)),
            height: max(64, min(size.height, 400))
        )

        // Look Around — osobny try/catch; przy asercji/błędzie spadamy na mapę.
        if let lookAround = await lookAroundSnapshotSafe(at: coordinate, size: safe) {
            return lookAround
        }
        return await mapSnapshotSafe(at: coordinate, size: safe)
    }

    private static func lookAroundSnapshotSafe(
        at coordinate: CLLocationCoordinate2D,
        size: CGSize
    ) async -> UIImage? {
        // Krótki timeout — Look Around bywa wolny / problematyczny.
        do {
            return try await withThrowingTaskGroup(of: UIImage?.self) { group in
                group.addTask { @MainActor in
                    await self.lookAroundSnapshot(at: coordinate, size: size)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                if let first = try await group.next() {
                    return first
                }
                return nil
            }
        } catch {
            return nil
        }
    }

    private static func lookAroundSnapshot(
        at coordinate: CLLocationCoordinate2D,
        size: CGSize
    ) async -> UIImage? {
        do {
            let request = MKLookAroundSceneRequest(coordinate: coordinate)
            guard let scene = try await request.scene else { return nil }
            let options = MKLookAroundSnapshotter.Options()
            options.size = size
            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
            let snap = try await snapshotter.snapshot
            // Skopiuj bitmapę — uniknij dangling buffer z MapKit.
            guard let cg = snap.image.cgImage else { return snap.image }
            return UIImage(cgImage: cg, scale: snap.image.scale, orientation: snap.image.imageOrientation)
        } catch {
            return nil
        }
    }

    private static func mapSnapshotSafe(
        at coordinate: CLLocationCoordinate2D,
        size: CGSize
    ) async -> UIImage? {
        do {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 220,
                longitudinalMeters: 220
            )
            options.size = size
            options.mapType = .standard
            options.pointOfInterestFilter = .includingAll
            // NIE ustawiaj traitCollection — znany program assert na wątku snapshottera.

            let snap = try await MKMapSnapshotter(options: options).start()
            guard let cg = snap.image.cgImage else { return snap.image }
            return UIImage(cgImage: cg, scale: snap.image.scale, orientation: .up)
        } catch {
            return nil
        }
    }
}
