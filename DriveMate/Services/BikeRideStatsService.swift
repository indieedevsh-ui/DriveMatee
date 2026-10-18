import Foundation
import CoreLocation
import HealthKit
import Combine
import MapKit

/// Statystyki jazdy rowerowej + tętno z HealthKit / Apple Watch.
@MainActor
final class BikeRideStatsService: ObservableObject {
    static let shared = BikeRideStatsService()

    @Published private(set) var heartRateBPM: Int?
    @Published private(set) var averageSpeedKmh: Double = 0
    @Published private(set) var maxAltitudeMeters: Double = 0
    @Published private(set) var currentAltitudeMeters: Double = 0
    @Published private(set) var healthAuthorized = false
    @Published private(set) var healthError: String?

    private let store = HKHealthStore()
    private var heartQuery: HKAnchoredObjectQuery?
    private var speedSamples: [Double] = []
    private var isTracking = false

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestHealthAccess() async {
        guard isHealthDataAvailable else {
            healthError = "HealthKit niedostępny na tym urządzeniu."
            return
        }
        guard let heart = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [heart])
            healthAuthorized = true
            healthError = nil
            startHeartRateQuery()
        } catch {
            healthAuthorized = false
            healthError = error.localizedDescription
        }
    }

    func startTrackingRide() {
        isTracking = true
        speedSamples = []
        averageSpeedKmh = 0
        maxAltitudeMeters = 0
    }

    func stopTrackingRide() {
        isTracking = false
    }

    func ingest(location: CLLocation, displayedSpeedKmh: Int) {
        let alt = location.altitude
        if alt.isFinite {
            currentAltitudeMeters = alt
            if isTracking {
                maxAltitudeMeters = max(maxAltitudeMeters, alt)
            } else if maxAltitudeMeters == 0 {
                maxAltitudeMeters = alt
            }
        }
        guard isTracking, displayedSpeedKmh >= 3 else { return }
        speedSamples.append(Double(displayedSpeedKmh))
        if speedSamples.count > 400 { speedSamples.removeFirst(speedSamples.count - 400) }
        averageSpeedKmh = speedSamples.reduce(0, +) / Double(speedSamples.count)
    }

    private func startHeartRateQuery() {
        heartQuery.map { store.stop($0) }
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-60 * 30),
            end: nil,
            options: .strictStartDate
        )
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.applyHeartSamples(samples)
            }
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.applyHeartSamples(samples)
            }
        }
        heartQuery = query
        store.execute(query)
    }

    private func applyHeartSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let last = quantitySamples.last else { return }
        let bpm = last.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        heartRateBPM = Int(bpm.rounded())
    }
}
