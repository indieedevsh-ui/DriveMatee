import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationSpeedService: NSObject, ObservableObject {
    @Published private(set) var speedKmh: Int = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    /// Czy użytkownik jest w ruchu (na podstawie GPS).
    @Published private(set) var isMoving = false

    private let manager = CLLocationManager()
    private var lastPublishedCoordinate: CLLocationCoordinate2D?
    private var lastSpeedPublish: Int = -1
    private var stationarySince: Date?

    /// Wygładzona prędkość (m/s).
    private var smoothedSpeedMps: Double = 0
    private var lastLocationForDelta: CLLocation?
    private var recentSpeedSamples: [Double] = []

    /// Poniżej tego progu (km/h) pokazujemy 0 — spacer / szum GPS.
    private let displayFloorKmh = 3.0
    /// Prędkość GPS poniżej tego (m/s ≈ 0.7 km/h) traktuj jako postój.
    private let rawStillMps = 0.45

    /// true gdy jedzie LUB stoi krócej niż 5 minut (warunek oferty restauracji).
    var allowsNearbyFoodOffer: Bool {
        if isMoving { return true }
        guard let stationarySince else { return true }
        return Date().timeIntervalSince(stationarySince) < 5 * 60
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
    }

    func requestAccessAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

extension LocationSpeedService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.ingest(location)
        }
    }

    private func ingest(_ location: CLLocation) {
        // Odrzuć bardzo niepewne pozycje
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 65 {
            return
        }

        let newCoord = location.coordinate
        if let last = lastPublishedCoordinate {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: location)
            if moved >= 6 {
                lastPublishedCoordinate = newCoord
                coordinate = newCoord
            }
        } else {
            lastPublishedCoordinate = newCoord
            coordinate = newCoord
        }

        let filteredMps = realisticSpeedMps(from: location)
        // EMA — mocniejsze wygładzenie przy niskich prędkościach
        let alpha = filteredMps < 2.0 ? 0.22 : 0.38
        if smoothedSpeedMps <= 0.01 {
            smoothedSpeedMps = filteredMps
        } else {
            smoothedSpeedMps = smoothedSpeedMps * (1 - alpha) + filteredMps * alpha
        }

        // Mediana z ostatnich próbek — tłumi pojedyncze skoki (np. 11 km/h przy spacerze)
        recentSpeedSamples.append(smoothedSpeedMps)
        if recentSpeedSamples.count > 5 {
            recentSpeedSamples.removeFirst()
        }
        let medianMps = median(recentSpeedSamples)
        var kmh = medianMps * 3.6

        // Deadband: wolny spacer / drganie GPS → 0
        if kmh < displayFloorKmh {
            kmh = 0
            smoothedSpeedMps *= 0.7
        }

        // Przy słabej dokładności prędkości nie podbijaj wskazań
        if location.speedAccuracy > 0, location.speedAccuracy > 1.8, kmh < 15 {
            kmh = min(kmh, max(0, (location.speed >= 0 ? location.speed : 0) * 3.6))
            if kmh < displayFloorKmh { kmh = 0 }
        }

        let display = Int(kmh.rounded())
        let nowMoving = display >= 4
        if nowMoving {
            isMoving = true
            stationarySince = nil
        } else {
            if isMoving || stationarySince == nil {
                stationarySince = Date()
            }
            isMoving = false
        }

        if abs(display - lastSpeedPublish) >= 1 || (display == 0 && lastSpeedPublish != 0) {
            lastSpeedPublish = display
            speedKmh = display
        }

        lastLocationForDelta = location
    }

    /// Realistyczna prędkość w m/s z GPS + sanity check dystansu/czasu.
    private func realisticSpeedMps(from location: CLLocation) -> Double {
        var candidates: [Double] = []

        // 1) Natywna prędkość GPS (gdy wiarygodna)
        if location.speed >= 0 {
            let speedAccOK = location.speedAccuracy < 0 || location.speedAccuracy <= 2.5
            if speedAccOK {
                candidates.append(max(0, location.speed))
            } else if location.speed < rawStillMps {
                candidates.append(0)
            }
        }

        // 2) Prędkość z delty pozycji (tylko przy sensownym dt)
        if let prev = lastLocationForDelta {
            let dt = location.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0.35, dt < 4.0 {
                let dist = location.distance(from: prev)
                // Odrzuć skoki GPS
                if dist < 80 {
                    let derived = dist / dt
                    // Przy krótkim dystansie i „wysokiej” prędkości — to szum
                    if dist < 2.5, derived > 1.5 {
                        candidates.append(0)
                    } else {
                        candidates.append(derived)
                    }
                }
            }
        }

        guard !candidates.isEmpty else { return 0 }

        // Bierz niższą z wiarygodnych — mniej fałszywych „11 km/h” przy staniu/spacerze
        let chosen = candidates.min() ?? 0
        if chosen < rawStillMps { return 0 }
        return chosen
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
