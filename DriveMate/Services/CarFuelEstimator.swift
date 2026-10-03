import Foundation

/// Szacunek spalania (l/100 km) na podstawie modelu auta.
enum CarFuelEstimator {
    static func litersPer100km(forModel model: String) -> Double {
        let m = model.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))

        // Hybrydy / EV-ish
        if m.contains("hybrid") || m.contains("hybryda") || m.contains("prius") { return 4.5 }
        if m.contains("electric") || m.contains("ev ") || m.hasSuffix(" ev") || m.contains("tesla") {
            return 0 // kWh — traktujemy osobno; 0 = brak litrów
        }

        // Diesle
        if m.contains("tdi") || m.contains("cdi") || m.contains("dci") || m.contains("diesel")
            || m.contains(" 320d") || m.contains(" 520d") || m.contains(" 220d") {
            return 5.8
        }

        // Małe miejskie
        if m.contains("fiesta") || m.contains("polo") || m.contains("corsa") || m.contains("yaris")
            || m.contains("fabia") || m.contains("clio") || m.contains("i20") || m.contains("swift") {
            return 5.5
        }

        // Kompakty
        if m.contains("golf") || m.contains("focus") || m.contains("civic") || m.contains("corolla")
            || m.contains("octavia") || m.contains("astra") || m.contains("megane") || m.contains("a3")
            || m.contains("serie 1") || m.contains("1 series") {
            return 6.2
        }

        // Średnie / sedan
        if m.contains("passat") || m.contains("mondeo") || m.contains("camry") || m.contains("a4")
            || m.contains("c-class") || m.contains("c class") || m.contains("3 series") || m.contains("seria 3")
            || m.contains("superb") {
            return 6.8
        }

        // SUV / większe
        if m.contains("suv") || m.contains("tucson") || m.contains("sportage") || m.contains("qashqai")
            || m.contains("x3") || m.contains("x5") || m.contains("q5") || m.contains("glc")
            || m.contains("rav4") || m.contains("cr-v") || m.contains("kodiaq") || m.contains("tiguan") {
            return 8.2
        }

        // Van / bus
        if m.contains("transporter") || m.contains("vivaro") || m.contains("trafic") || m.contains("sprinter") {
            return 9.5
        }

        return 7.0
    }

    static let defaultFuelPricePLNPerLiter: Double = 6.50
}
