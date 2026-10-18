import Foundation
import CoreLocation
import WeatherKit
import Combine

/// Ostrzeżenia pogodowe WeatherKit na czas trasy (ETA).
@MainActor
final class WeatherRouteAdvisoryService: ObservableObject {
    static let shared = WeatherRouteAdvisoryService()

    @Published private(set) var lastSpokenKey: String?
    private var advisedTripIDs: Set<String> = []

    /// Po zaplanowaniu trasy — sprawdź pogodę; mów: „O x godzinie może pojawić się y…”.
    func adviseIfNeeded(
        start: CLLocationCoordinate2D?,
        destination: CLLocationCoordinate2D?,
        travelSeconds: TimeInterval,
        tripKey: String,
        speak: @escaping (String) -> Void
    ) {
        guard !advisedTripIDs.contains(tripKey) else { return }
        guard let start else { return }

        Task {
            do {
                let hazards = try await collectHazards(
                    start: start,
                    destination: destination,
                    travelSeconds: travelSeconds
                )
                guard let best = hazards.first else { return }
                advisedTripIDs.insert(tripKey)
                lastSpokenKey = best.id
                speak(best.spokenSentence)
            } catch {
                // Brak WeatherKit / uprawnień — cicho pomiń.
            }
        }
    }

    func reset() {
        advisedTripIDs.removeAll()
        lastSpokenKey = nil
    }

    private struct Hazard: Identifiable {
        let id: String
        let hourLabel: String
        let name: String
        var spokenSentence: String {
            "O \(hourLabel) może pojawić się \(name), więc odpowiednio przygotuj się."
        }
    }

    private func collectHazards(
        start: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D?,
        travelSeconds: TimeInterval
    ) async throws -> [Hazard] {
        let service = WeatherService.shared
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLoc: CLLocation = {
            if let destination {
                return CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            }
            return startLoc
        }()

        async let startWeather = service.weather(for: startLoc)
        async let endWeather = service.weather(for: endLoc)
        let (sw, ew) = try await (startWeather, endWeather)

        let arrival = Date().addingTimeInterval(max(travelSeconds, 600))
        let windowEnd = arrival.addingTimeInterval(45 * 60)

        var found: [Hazard] = []
        found.append(contentsOf: scanHourly(sw.hourlyForecast, from: Date(), to: windowEnd))
        found.append(contentsOf: scanHourly(ew.hourlyForecast, from: Date(), to: windowEnd))

        var seen = Set<String>()
        return found
            .sorted { $0.hourLabel < $1.hourLabel }
            .filter { seen.insert($0.id).inserted }
    }

    private func scanHourly(
        _ forecast: Forecast<HourWeather>,
        from start: Date,
        to end: Date
    ) -> [Hazard] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "H:mm"

        var out: [Hazard] = []
        for hour in forecast {
            guard hour.date >= start.addingTimeInterval(-300), hour.date <= end else { continue }
            if let name = hazardName(for: hour) {
                let label = formatter.string(from: hour.date)
                out.append(Hazard(id: "\(label)-\(name)", hourLabel: label, name: name))
            }
        }
        return out
    }

    private func hazardName(for hour: HourWeather) -> String? {
        let key = String(describing: hour.condition).lowercased()
        if key.contains("thunder") || key.contains("storm") {
            return "burza"
        }
        if key.contains("hail") {
            return "grad"
        }
        if key.contains("freezing") {
            return "marznący deszcz"
        }
        if key.contains("snow") || key.contains("flurries") || key.contains("blizzard") {
            return "śnieg"
        }
        if key.contains("fog") || key.contains("haze") || key.contains("smoke") {
            return "ograniczona widoczność"
        }
        if key.contains("rain") || key.contains("shower") || key.contains("drizzle") {
            return "deszcz"
        }
        if hour.wind.speed.converted(to: .kilometersPerHour).value >= 50 {
            return "silny wiatr"
        }
        if hour.precipitationChance >= 0.55 {
            return "deszcz"
        }
        return nil
    }
}
