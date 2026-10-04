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
    /// Ile kolejnych „ruchomych” próbek zanim pokażemy prędkość > 0.
    private var movingStreak = 0
    private var stillStreak = 0

    /// Poniżej tego (km/h) zawsze 0 — szum GPS / mikrodrgania.
    private let displayFloorKmh = 8.0
    /// GPS speed poniżej tego (m/s ≈ 2.5 km/h) = postój.
    private let rawStillMps = 0.70
    /// Wymagana dokładność pozycji do wiarygodnej prędkości (m).
    private let maxAccuracyForSpeed: CLLocationAccuracy = 35
    /// Ile próbek ruchu z rzędu, by wyjść z zera.
    private let movingConfirmCount = 3

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
        // Odrzuć niepewne pozycje
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 80 {
            return
        }

        let newCoord = location.coordinate
        if let last = lastPublishedCoordinate {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: location)
            if moved >= 8 {
                lastPublishedCoordinate = newCoord
                coordinate = newCoord
            }
        } else {
            lastPublishedCoordinate = newCoord
            coordinate = newCoord
        }

        // Słaba dokładność pozycji → nie zgaduj prędkości (typowy fałszywy „6 km/h” w miejscu)
        if location.horizontalAccuracy > maxAccuracyForSpeed {
            forceStationary()
            lastLocationForDelta = location
            return
        }

        let filteredMps = realisticSpeedMps(from: location)

        // EMA — przy niskich prędkościach mocno tłum
        let alpha = filteredMps < 2.5 ? 0.14 : 0.32
        if smoothedSpeedMps <= 0.01 {
            smoothedSpeedMps = filteredMps
        } else {
            smoothedSpeedMps = smoothedSpeedMps * (1 - alpha) + filteredMps * alpha
        }

        recentSpeedSamples.append(smoothedSpeedMps)
        if recentSpeedSamples.count > 7 {
            recentSpeedSamples.removeFirst()
        }
        let medianMps = median(recentSpeedSamples)
        var kmh = medianMps * 3.6

        // Deadband + szybki powrót do zera
        if kmh < displayFloorKmh {
            kmh = 0
            smoothedSpeedMps *= 0.45
        }

        // Słaba dokładność prędkości GPS
        if location.speedAccuracy >= 0, location.speedAccuracy > 1.2, kmh < 25 {
            let rawKmh = location.speed >= 0 ? location.speed * 3.6 : 0
            kmh = min(kmh, max(0, rawKmh))
            if kmh < displayFloorKmh { kmh = 0 }
        }

        // Histereza: nie pokazuj ruchu po jednej szumowej próbce
        if kmh >= displayFloorKmh {
            movingStreak += 1
            stillStreak = 0
        } else {
            stillStreak += 1
            movingStreak = 0
            kmh = 0
        }

        var display = Int(kmh.rounded())
        if movingStreak < movingConfirmCount {
            display = 0
        }
        // Po 2 próbkach postoju — natychmiast 0
        if stillStreak >= 2 {
            display = 0
            smoothedSpeedMps = 0
        }

        let nowMoving = display >= Int(displayFloorKmh.rounded())
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

    private func forceStationary() {
        movingStreak = 0
        stillStreak += 1
        smoothedSpeedMps *= 0.3
        recentSpeedSamples.append(0)
        if recentSpeedSamples.count > 7 { recentSpeedSamples.removeFirst() }
        if speedKmh != 0 {
            lastSpeedPublish = 0
            speedKmh = 0
        }
        if isMoving || stationarySince == nil {
            stationarySince = Date()
        }
        isMoving = false
    }

    /// Realistyczna prędkość w m/s — preferuj natywne GPS speed; delta pozycji tylko jako sanity check.
    private func realisticSpeedMps(from location: CLLocation) -> Double {
        var gpsSpeed: Double?

        if location.speed >= 0 {
            let speedAccOK = location.speedAccuracy < 0 || location.speedAccuracy <= 1.6
            if speedAccOK {
                gpsSpeed = max(0, location.speed)
            } else if location.speed < rawStillMps {
                gpsSpeed = 0
            }
        }

        var derivedSpeed: Double?
        if let prev = lastLocationForDelta {
            let dt = location.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0.5, dt < 3.5 {
                let dist = location.distance(from: prev)
                // Mały dystans w krótkim czasie = szum, nie jazda
                if dist < 1.8 {
                    derivedSpeed = 0
                } else if dist < 60 {
                    let derived = dist / dt
                    // Przy słabej dokładności nie ufaj delcie
                    if location.horizontalAccuracy <= 25, derived < 25 {
                        derivedSpeed = derived
                    }
                }
            }
        }

        // Gdy GPS mówi ~0 — wierzymy GPS (nie podbijaj delcie pozycji)
        if let gps = gpsSpeed, gps < rawStillMps {
            return 0
        }

        var candidates: [Double] = []
        if let gps = gpsSpeed { candidates.append(gps) }
        if let derived = derivedSpeed { candidates.append(derived) }
        guard !candidates.isEmpty else { return 0 }

        // Najniższa wiarygodna — unika fałszywych km/h przy postoju
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
