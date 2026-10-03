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
        manager.distanceFilter = 5
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
            let newCoord = location.coordinate
            if let last = lastPublishedCoordinate {
                let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: location)
                if moved < 8 { /* skip tiny moves */ } else {
                    lastPublishedCoordinate = newCoord
                    coordinate = newCoord
                }
            } else {
                lastPublishedCoordinate = newCoord
                coordinate = newCoord
            }

            if location.speed >= 0 {
                let kmh = Int((location.speed * 3.6).rounded())
                let nowMoving = kmh >= 4
                if nowMoving {
                    isMoving = true
                    stationarySince = nil
                } else {
                    if isMoving || stationarySince == nil {
                        stationarySince = Date()
                    }
                    isMoving = false
                }
                if abs(kmh - lastSpeedPublish) >= 1 {
                    lastSpeedPublish = kmh
                    speedKmh = kmh
                }
            }
        }
    }
}
