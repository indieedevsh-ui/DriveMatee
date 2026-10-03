import Foundation
import FoundationModels
import MapKit
import CoreLocation
import NaturalLanguage

// MARK: - Tools (Foundation Models + MapKit / NaturalLanguage)

struct FindPlaceTool: Tool {
    let name = "findPlace"
    let description = """
        Wyszukuje miejsce, adres lub POI przez Apple Maps (MKLocalSearch). \
        Używaj gdy kierowca podaje cel nawigacji lub pyta o lokalizację.
        """

    @Generable
    struct Arguments {
        @Guide(description: "Zapytanie miejsca, np. nazwa ulicy, miasta lub POI")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let coordinate = await MapKitNavigationService.shared.location?.coordinate
        let places = try await MapKitNavigationService.shared.searchPlaces(
            query: arguments.query,
            near: coordinate
        )
        guard !places.isEmpty else {
            return "Nie znaleziono miejsc dla „\(arguments.query)”."
        }
        return places.enumerated().map { index, place in
            """
            [\(index + 1)] \(place.name)
            adres: \(place.address)
            lat: \(place.latitude), lon: \(place.longitude)
            kategoria: \(place.category)
            """
        }.joined(separator: "\n\n")
    }
}

struct PlanBestRouteTool: Tool {
    let name = "planBestRoute"
    let description = """
        Liczy trasę samochodową Apple Maps (MKDirections) i uruchamia nawigację. \
        Wywołuj TYLKO gdy znasz cel (lat/lon) ORAZ skąd startuje kierowca \
        (moja lokalizacja albo jawny punkt startowy). \
        NIE wywołuj, gdy start jest nieznany — wtedy zapytaj kierowcę.
        """

    @Generable
    struct Arguments {
        @Guide(description: "Nazwa miejsca docelowego do wyświetlenia kierowcy")
        var destinationName: String
        @Guide(description: "Szerokość geograficzna celu")
        var latitude: Double
        @Guide(description: "Długość geograficzna celu")
        var longitude: Double
        @Guide(description: "true gdy start z bieżącej lokalizacji GPS kierowcy")
        var fromCurrentLocation: Bool
        @Guide(description: "Szerokość startu gdy fromCurrentLocation=false; inaczej 0")
        var fromLatitude: Double
        @Guide(description: "Długość startu gdy fromCurrentLocation=false; inaczej 0")
        var fromLongitude: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let fromLat: Double?
        let fromLon: Double?
        if arguments.fromCurrentLocation {
            fromLat = nil
            fromLon = nil
        } else if abs(arguments.fromLatitude) > 0.01, abs(arguments.fromLongitude) > 0.01 {
            fromLat = arguments.fromLatitude
            fromLon = arguments.fromLongitude
        } else {
            return """
            Brak punktu startowego. Nie uruchamiam trasy. \
            Zapytaj kierowcę: „Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?”
            """
        }

        let result = try await MapKitNavigationService.shared.planBestRoute(
            toLatitude: arguments.latitude,
            toLongitude: arguments.longitude,
            destinationName: arguments.destinationName,
            fromLatitude: fromLat,
            fromLongitude: fromLon
        )

        var text = """
        Wybrano najlepszą trasę (priorytet: ETA z ruchem, potem dystans):
        \(result.best.summary)
        """
        if !result.alternates.isEmpty {
            text += "\n\nAlternatywy:\n"
            text += result.alternates.map(\.summary).joined(separator: "\n")
        }
        text += "\n\nNawigacja uruchomiona. Potwierdź kierowcy jednym krótkim zdaniem (cel + czas)."
        return text
    }
}

struct TrafficRiskTool: Tool {
    let name = "assessTrafficRisk"
    let description = """
        Ocenia ryzyko korków i problemów z przejazdem wokół wskazanego punktu \
        na podstawie ETA Apple Maps (MKDirections) oraz NaturalLanguage.
        """

    @Generable
    struct Arguments {
        @Guide(description: "Szerokość geograficzna punktu do analizy")
        var latitude: Double
        @Guide(description: "Długość geograficzna punktu do analizy")
        var longitude: Double
        @Guide(description: "Opcjonalna nazwa ulicy lub okolicy")
        var areaName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let coordinate = CLLocationCoordinate2D(
            latitude: arguments.latitude,
            longitude: arguments.longitude
        )
        let traffic = try await MapKitNavigationService.shared.trafficSnapshot(near: coordinate)

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        let label = arguments.areaName ?? "okolica"
        tagger.string = label
        var tokens: [String] = []
        tagger.enumerateTags(
            in: label.startIndex..<label.endIndex,
            unit: .word,
            scheme: .lexicalClass
        ) { tag, range in
            if let tag {
                tokens.append("\(label[range])=\(tag.rawValue)")
            }
            return true
        }

        return """
        Analiza ruchu dla: \(label)
        Współrzędne: \(arguments.latitude), \(arguments.longitude)

        \(traffic)

        NaturalLanguage (tokeny): \(tokens.isEmpty ? "brak" : tokens.joined(separator: ", "))

        Uwaga: dane ruchu pochodzą z Apple Maps; roboty drogowe mogą być ujęte w advisoryNotices trasy.
        """
    }
}

struct StreetInsightTool: Tool {
    let name = "streetInsight"
    let description = """
        Zwraca kontekst ulicy: adres Apple Maps (CLGeocoder/MapKit), \
        kategorię NL oraz wskazówki ryzyka przejazdu. Historia ulicy jest \
        uzupełniana przez model Foundation Models na podstawie nazwy miejsca.
        """

    @Generable
    struct Arguments {
        @Guide(description: "Nazwa ulicy lub miejsca")
        var streetOrPlace: String
        @Guide(description: "Szerokość geograficzna jeśli znana, inaczej 0")
        var latitude: Double
        @Guide(description: "Długość geograficzna jeśli znana, inaczej 0")
        var longitude: Double
    }

    func call(arguments: Arguments) async throws -> String {
        var placemarkInfo = ""
        var coordinate = CLLocationCoordinate2D(
            latitude: arguments.latitude,
            longitude: arguments.longitude
        )

        if abs(arguments.latitude) < 0.0001, abs(arguments.longitude) < 0.0001 {
            let near = await MapKitNavigationService.shared.location?.coordinate
            let places = try await MapKitNavigationService.shared.searchPlaces(
                query: arguments.streetOrPlace,
                near: near
            )
            if let first = places.first {
                coordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
                placemarkInfo = "\(first.name), \(first.address)"
            }
        } else {
            let placemark = try await MapKitNavigationService.shared.reverseGeocode(coordinate: coordinate)
            placemarkInfo = [
                placemark.thoroughfare,
                placemark.subThoroughfare,
                placemark.locality,
                placemark.administrativeArea
            ].compactMap { $0 }.joined(separator: ", ")
            await MapComplianceStore.shared.showPlace(
                name: placemarkInfo.isEmpty ? arguments.streetOrPlace : placemarkInfo,
                coordinate: coordinate
            )
        }

        let embedding = NLEmbedding.wordEmbedding(for: .polish)
        let related = embedding?.neighbors(for: "ulica", maximumCount: 5).map(\.0) ?? []

        let traffic: String
        if abs(coordinate.latitude) > 0.01 {
            traffic = (try? await MapKitNavigationService.shared.trafficSnapshot(near: coordinate)) ?? "Brak ETA."
        } else {
            traffic = "Brak współrzędnych do oceny ruchu."
        }

        return """
        Ulica / miejsce: \(arguments.streetOrPlace)
        MapKit / geokodowanie: \(placemarkInfo.isEmpty ? "brak" : placemarkInfo)
        Współrzędne: \(coordinate.latitude), \(coordinate.longitude)
        NaturalLanguage sąsiedztwo semantyczne (PL): \(related.joined(separator: ", "))

        Ruch w okolicy:
        \(traffic)

        Poproś model o krótką, ostrożną notę historyczną ulicy (fakt lub legenda lokalna) \
        oraz praktyczne ryzyka przejazdu (szkoły, wąskie ulice, korki godzin szczytu).
        """
    }
}
