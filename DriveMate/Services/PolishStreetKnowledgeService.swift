import Foundation
import CoreLocation

/// Wiedza o ulicach PL — max 3 oficjalne / wysokiej jakości źródła:
/// 1) GUGiK PRG przez OGC API Features (ulice + punkty adresowe + kody TERYT)
/// 2) Nominatim UMP (OSM PL) — kontekst mapowy
/// 3) Wikipedia PL — ciekawostki / historia nazwy
@MainActor
enum PolishStreetKnowledgeService {

    struct Snapshot: Sendable {
        var streetName: String
        var city: String?
        var municipality: String?
        var postcode: String?
        var houseNumber: String?
        var terytULIC: String?
        var terytSIMC: String?
        var terytGmina: String?
        var streetKind: String?
        var osmContext: String?
        var wikipediaExtract: String?
        var sources: [String]

        var spokenSummary: String {
            // Tylko naturalna narracja — bez kodów TERYT/SIMC/TERC, kodów pocztowych itd.
            let place = narrativePlaceLabel
            if let wiki = wikipediaExtract, !wiki.isEmpty {
                let lowerWiki = wiki.lowercased()
                let shortName = streetName
                    .replacingOccurrences(of: "ulica ", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if lowerWiki.contains(shortName.lowercased()) || lowerWiki.hasPrefix("ulic") {
                    return wiki
                }
                return "\(place). \(wiki)"
            }

            var parts: [String] = [place + "."]
            if let district = humanDistrict, !district.isEmpty {
                parts.append("Leży w okolicy \(district).")
            }
            if let kind = friendlyKind, !kind.isEmpty {
                parts.append("To \(kind).")
            }
            if parts.count == 1 {
                parts.append("Nie mam teraz pewnej ciekawostki historycznej o tym miejscu.")
            }
            return parts.joined(separator: " ")
        }

        var cardBody: String { spokenSummary }

        var hasCuriosity: Bool {
            !(wikipediaExtract ?? "").isEmpty
        }

        var narrativePlaceLabel: String {
            let name = streetName.trimmingCharacters(in: .whitespacesAndNewlines)
            let withPrefix: String = {
                let lower = name.lowercased()
                if lower.hasPrefix("ul.") || lower.hasPrefix("ulica") || lower.hasPrefix("al.")
                    || lower.hasPrefix("aleja") || lower.hasPrefix("pl.") || lower.hasPrefix("plac")
                    || lower.hasPrefix("os.") || lower.hasPrefix("osiedle") {
                    return name
                }
                return "ulica \(name)"
            }()
            if let city, !city.isEmpty {
                return "\(withPrefix) w \(city)"
            }
            return withPrefix
        }

        private var humanDistrict: String? {
            if let osmContext, !osmContext.isEmpty { return osmContext }
            if let municipality, !municipality.isEmpty,
               municipality.caseInsensitiveCompare(city ?? "") != .orderedSame {
                return municipality
            }
            return nil
        }

        private var friendlyKind: String? {
            guard let streetKind, !streetKind.isEmpty else { return nil }
            let k = streetKind.lowercased()
            if k.contains("plac") { return "plac" }
            if k.contains("alej") { return "aleja" }
            if k.contains("osied") { return "osiedle" }
            if k.contains("skwer") { return "skwer" }
            if k.contains("rond") { return "rondo" }
            if k.contains("ulic") { return "ulica" }
            // Unikaj surowych etykiet rejestru
            if k.count <= 24, !k.contains(where: \.isNumber) { return k }
            return nil
        }
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4.5
        cfg.timeoutIntervalForResource = 6
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private static let userAgent = "DriveMate/1.0 (iOS; Polish street knowledge; contact: drivemate@local)"

    /// Równolegle: PRG/OGC (+TERYT) + Nominatim + Wikipedia (opcjonalnie).
    static func lookup(
        coordinate: CLLocationCoordinate2D,
        preferredName: String?,
        wantCuriosity: Bool
    ) async -> Snapshot? {
        async let prg = fetchPRG(near: coordinate, preferredName: preferredName)
        async let osm = fetchNominatim(near: coordinate)
        let prgHit = await prg
        let osmHit = await osm

        var street = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if street.isEmpty { street = prgHit?.street ?? osmHit?.road ?? "" }
        if street.isEmpty { return nil }

        let city = prgHit?.city ?? osmHit?.city
        var wiki: String?
        if wantCuriosity {
            wiki = await fetchWikipediaCuriosity(street: street, city: city)
        }

        var sources: [String] = []
        if prgHit != nil { sources.append("GUGiK PRG / OGC") }
        if prgHit?.ulic != nil || prgHit?.simc != nil { sources.append("GUS TERYT") }
        if osmHit != nil { sources.append("Nominatim OSM") }
        if wiki != nil { sources.append("Wikipedia PL") }

        return Snapshot(
            streetName: street,
            city: city,
            municipality: prgHit?.gmina ?? osmHit?.city,
            postcode: prgHit?.postcode ?? osmHit?.postcode,
            houseNumber: prgHit?.number ?? osmHit?.houseNumber,
            terytULIC: prgHit?.ulic,
            terytSIMC: prgHit?.simc,
            terytGmina: prgHit?.terc,
            streetKind: prgHit?.kind,
            osmContext: osmHit?.contextSentence,
            wikipediaExtract: wiki,
            sources: sources
        )
    }

    // MARK: - 1) GUGiK PRG OGC API Features (+ kody TERYT)

    private struct PRGHit {
        var street: String
        var city: String?
        var gmina: String?
        var postcode: String?
        var number: String?
        var ulic: String?
        var simc: String?
        var terc: String?
        var kind: String?
    }

    private static func fetchPRG(
        near coordinate: CLLocationCoordinate2D,
        preferredName: String?
    ) async -> PRGHit? {
        let d = 0.0012
        let bbox = "\(coordinate.longitude - d),\(coordinate.latitude - d),\(coordinate.longitude + d),\(coordinate.latitude + d)"
        guard var comps = URLComponents(string: "https://ogcapi.geoportal.gov.pl/res/ims/maps/prg_ad/apiFeatures/collections/PunktAdresowy/items") else {
            return nil
        }
        comps.queryItems = [
            URLQueryItem(name: "bbox", value: bbox),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = comps.url,
              let json = await getJSON(url: url) as? [String: Any],
              let features = json["features"] as? [[String: Any]],
              !features.isEmpty else { return nil }

        let preferred = preferredName?
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
            .lowercased()

        func props(_ f: [String: Any]) -> [String: Any] {
            f["properties"] as? [String: Any] ?? [:]
        }

        let chosen: [String: Any] = {
            if let preferred, !preferred.isEmpty,
               let match = features.first(where: {
                   let n = (props($0)["nazwaUlicy"] as? String ?? "")
                       .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
                       .lowercased()
                   return n.contains(preferred) || preferred.contains(n)
               }) {
                return props(match)
            }
            return props(features[0])
        }()

        guard let street = chosen["nazwaUlicy"] as? String, !street.isEmpty else { return nil }
        return PRGHit(
            street: street,
            city: chosen["nazwaMiejscowosci"] as? String,
            gmina: chosen["nazwaGminy"] as? String,
            postcode: chosen["kodPocztowy"] as? String,
            number: chosen["numerPorzadkowy"] as? String,
            ulic: chosen["idULICNazwyUlicy"] as? String,
            simc: chosen["idSIMCNazwyMiejscowosci"] as? String,
            terc: chosen["terytGminy"] as? String,
            kind: chosen["rodzaj"] as? String ?? "ulica / plac"
        )
    }

    // MARK: - 2) Nominatim UMP (OSM PL)

    private struct OSMHit {
        var road: String?
        var city: String?
        var postcode: String?
        var houseNumber: String?
        var contextSentence: String?
    }

    private static func fetchNominatim(near coordinate: CLLocationCoordinate2D) async -> OSMHit? {
        guard var comps = URLComponents(string: "https://nominatim.ump.waw.pl/reverse") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
            URLQueryItem(name: "zoom", value: "17"),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "accept-language", value: "pl")
        ]
        guard let url = comps.url,
              let json = await getJSON(url: url) as? [String: Any] else { return nil }

        let address = json["address"] as? [String: Any] ?? [:]
        let road = (address["road"] as? String)
            ?? (address["pedestrian"] as? String)
            ?? (json["name"] as? String)
        let city = (address["city"] as? String)
            ?? (address["town"] as? String)
            ?? (address["village"] as? String)
        let suburb = address["suburb"] as? String

        var ctxParts: [String] = []
        if let suburb, !suburb.isEmpty { ctxParts.append(suburb) }
        // Bez technicznych etykiet OSM / kodów
        let ctx = ctxParts.isEmpty ? nil : ctxParts.joined(separator: ", ")

        return OSMHit(
            road: road,
            city: city,
            postcode: address["postcode"] as? String,
            houseNumber: address["house_number"] as? String,
            contextSentence: ctx
        )
    }

    // MARK: - 3) Wikipedia PL (ciekawostki)

    private static func fetchWikipediaCuriosity(street: String, city: String?) async -> String? {
        let cleanStreet = street
            .replacingOccurrences(of: "ulica ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var queries: [String] = []
        if let city, !city.isEmpty {
            queries.append("Ulica \(cleanStreet) (\(city))")
            queries.append("\(cleanStreet) (\(city))")
        }
        queries.append("Ulica \(cleanStreet)")
        queries.append(cleanStreet)

        for q in queries {
            if let extract = await wikipediaSummary(titleHint: q) {
                return shortenCuriosity(extract)
            }
        }
        return nil
    }

    private static func wikipediaSummary(titleHint: String) async -> String? {
        // 1) OpenSearch → tytuł
        guard var search = URLComponents(string: "https://pl.wikipedia.org/w/api.php") else { return nil }
        search.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: titleHint),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let searchURL = search.url,
              let arr = await getJSON(url: searchURL) as? [Any],
              arr.count >= 2,
              let titles = arr[1] as? [String],
              let title = titles.first,
              !title.isEmpty else { return nil }

        // 2) REST summary
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let sumURL = URL(string: "https://pl.wikipedia.org/api/rest_v1/page/summary/\(encoded)"),
              let json = await getJSON(url: sumURL) as? [String: Any] else { return nil }

        if let type = json["type"] as? String, type == "disambiguation" { return nil }
        let extract = (json["extract"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let extract, extract.count > 40 else { return nil }
        return extract
    }

    private static func shortenCuriosity(_ text: String) -> String {
        let trimmed = text.replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 280 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 260)
        if let dot = trimmed[..<idx].lastIndex(of: ".") {
            return String(trimmed[...dot])
        }
        return String(trimmed.prefix(260)) + "…"
    }

    // MARK: - HTTP

    private static func getJSON(url: URL) async -> Any? {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 4.5
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }
}
