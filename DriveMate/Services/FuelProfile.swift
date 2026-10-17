import Foundation
import CoreLocation
import Combine

/// Profil paliwa auta: pojemność baku, poziom, cena litra.
///
/// Poziom paliwa trzymany jest jako procent baku (0…1). Spadek poziomu liczony
/// ze przejechanego dystansu, więc zasięg odpowiada realnym możliwościom auta.
/// Wszystko leży w UserDefaults — nie ma tu dostępu do OBD.
@MainActor
final class FuelProfile: ObservableObject {
    static let shared = FuelProfile()

    private enum Keys {
        static let tankCapacity = "fuelTankCapacityL"
        static let levelPercent = "fuelLevelPercent"
        static let pricePerLiter = "fuelPricePLNPerLiter"
        static let consumptionOverride = "fuelConsumptionLPer100"
        static let carModel = "carModel"
    }

    private let defaults: UserDefaults

    @Published var tankCapacityLiters: Double {
        didSet { defaults.set(tankCapacityLiters, forKey: Keys.tankCapacity) }
    }

    @Published var pricePLNPerLiter: Double {
        didSet { defaults.set(pricePLNPerLiter, forKey: Keys.pricePerLiter) }
    }

    /// 0…1 — zapełnienie baku. 1 = pełny.
    @Published var levelPercent: Double {
        didSet { defaults.set(levelPercent, forKey: Keys.levelPercent) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedTank = defaults.double(forKey: Keys.tankCapacity)
        tankCapacityLiters = storedTank > 0 ? storedTank : 50
        levelPercent = min(max(defaults.object(forKey: Keys.levelPercent) as? Double ?? 1, 0), 1)

        let storedPrice = defaults.double(forKey: Keys.pricePerLiter)
        pricePLNPerLiter = storedPrice > 0 ? storedPrice : CarFuelEstimator.defaultFuelPricePLNPerLiter
    }

    // MARK: - Reads

    var carModel: String {
        (defaults.string(forKey: Keys.carModel) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// l/100 km — ręczne ustawienie, inaczej estymator z modelu.
    var consumptionLPer100: Double? {
        let manual = defaults.double(forKey: Keys.consumptionOverride)
        if manual > 0 { return manual }
        let estimated = CarFuelEstimator.litersPer100km(forModel: carModel)
        return estimated > 0 ? estimated : nil
    }

    /// Czy kierowca w ogóle ustawił auto — bez tego nie liczymy spalania.
    var hasCar: Bool {
        let manual = defaults.double(forKey: Keys.consumptionOverride)
        return manual > 0 || !carModel.isEmpty
    }

    var isElectric: Bool {
        let manual = defaults.double(forKey: Keys.consumptionOverride)
        if manual > 0 { return false }
        return carModel.isEmpty
            ? false
            : CarFuelEstimator.litersPer100km(forModel: carModel) == 0
    }

    /// Litry w baku przy bieżącym poziomie.
    func litersInTank() -> Double {
        tankCapacityLiters * levelPercent
    }

    /// Szacowany zasięg w km przy danym spalaniu.
    func rangeKm(consumption: Double? = nil) -> Double? {
        let cons = consumption ?? consumptionLPer100
        guard let cons, cons > 0 else { return nil }
        return litersInTank() / (cons / 100)
    }

    /// Na ile procent / ile km starczy na `distanceKm`.
    func sufficiency(distanceKm: Double, consumption: Double? = nil) -> (neededLiters: Double, levelPercentNeeded: Double, fits: Bool)? {
        guard let cons = consumption ?? consumptionLPer100, cons > 0, tankCapacityLiters > 0 else { return nil }
        let neededLiters = distanceKm * (cons / 100)
        let needed = tankCapacityLiters > 0 ? neededLiters / tankCapacityLiters : 0
        return (neededLiters, min(needed, 1), neededLiters <= litersInTank())
    }

    /// Rezerwa, przy której warto przypomnieć o tankowaniu (12% baku).
    static let reservePercent = 0.12

    var isBelowReserve: Bool { levelPercent <= Self.reservePercent }

    // MARK: - Writes

    func refill() {
        levelPercent = 1
    }

    func setLevelPercent(_ value: Double) {
        levelPercent = min(max(value, 0), 1)
    }

    /// Odejmie spalone litry po przejechaniu dystansu (wywoływane po zakończeniu trasy).
    func consume(distanceMeters: CLLocationDistance, consumption: Double? = nil) {
        guard distanceMeters > 0, let cons = consumption ?? consumptionLPer100, cons > 0 else { return }
        let burnedLiters = (distanceMeters / 1000) * (cons / 100)
        guard burnedLiters > 0 else { return }
        levelPercent = max(0, levelPercent - burnedLiters / tankCapacityLiters)
    }

    // MARK: - Formatting

    static func kmLabel(_ km: Double) -> String {
        if km >= 1000 { return String(format: "%.0f km", km) }
        if km >= 100 { return String(format: "%.0f km", km) }
        return String(format: "%.0f km", km)
    }

    static func percentLabel(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) procent"
    }
}