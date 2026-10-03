import SwiftUI
import MapKit
import CoreLocation
import Combine

/// Stan prezentacji Map Data na mapie Apple (wymóg Attachment 6 §2.4).
@MainActor
final class MapComplianceStore: ObservableObject {
    static let shared = MapComplianceStore()

    struct Pin: Identifiable, Equatable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
        let title: String

        init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, title: String) {
            self.id = id
            self.coordinate = coordinate
            self.title = title
        }

        static func == (lhs: Pin, rhs: Pin) -> Bool {
            lhs.id == rhs.id
        }
    }

    struct Surface: Equatable {
        var center: CLLocationCoordinate2D
        var spanMeters: CLLocationDistance
        var title: String
        var pins: [Pin]
        var routePolyline: MKPolyline?
        var showsTraffic: Bool

        static func == (lhs: Surface, rhs: Surface) -> Bool {
            lhs.center.latitude == rhs.center.latitude
                && lhs.center.longitude == rhs.center.longitude
                && lhs.title == rhs.title
                && lhs.pins.map(\.id) == rhs.pins.map(\.id)
                && lhs.showsTraffic == rhs.showsTraffic
                && (lhs.routePolyline == nil) == (rhs.routePolyline == nil)
        }
    }

    @Published private(set) var surface: Surface?

    func showPlace(
        name: String,
        coordinate: CLLocationCoordinate2D,
        spanMeters: CLLocationDistance = 1_200
    ) {
        surface = Surface(
            center: coordinate,
            spanMeters: spanMeters,
            title: name,
            pins: [Pin(coordinate: coordinate, title: name)],
            routePolyline: nil,
            showsTraffic: false
        )
    }

    func showPlaces(
        title: String,
        pins: [(CLLocationCoordinate2D, String)],
        center: CLLocationCoordinate2D?,
        spanMeters: CLLocationDistance = 2_500
    ) {
        guard !pins.isEmpty else { return }
        let mapped = pins.map { Pin(coordinate: $0.0, title: $0.1) }
        let c = center ?? mapped[0].coordinate
        surface = Surface(
            center: c,
            spanMeters: spanMeters,
            title: title,
            pins: mapped,
            routePolyline: nil,
            showsTraffic: false
        )
    }

    func showTraffic(
        near coordinate: CLLocationCoordinate2D,
        title: String,
        route: MKRoute?
    ) {
        surface = Surface(
            center: coordinate,
            spanMeters: route.map { max($0.distance * 0.6, 1_500) } ?? 3_000,
            title: title,
            pins: [Pin(coordinate: coordinate, title: title)],
            routePolyline: route?.polyline,
            showsTraffic: true
        )
    }

    func clear() {
        surface = nil
    }
}

/// Kompaktowa mapa Apple z atrubucją Legal — do wyników Map Data.
struct AppleMapDataPreview: View {
    var surface: MapComplianceStore.Surface
    var height: CGFloat = 140
    var cornerRadius: CGFloat = 18

    @State private var showLegal = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ComplianceMapView(surface: surface)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            Button {
                showLegal = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Maps · Legal")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(height: height)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        }
        .sheet(isPresented: $showLegal) {
            NavigationStack {
                List {
                    Section("Źródło") {
                        Text("Dane mapy, miejsc i tras pochodzą z Apple Maps (MapKit).")
                    }
                    Section {
                        Link(
                            "Apple Maps Legal",
                            destination: URL(string: "https://www.apple.com/legal/internet-services/maps/")!
                        )
                    }
                }
                .navigationTitle("Legal")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Gotowe") { showLegal = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .accessibilityLabel("Mapa Apple: \(surface.title)")
    }
}

private struct ComplianceMapView: UIViewRepresentable {
    var surface: MapComplianceStore.Surface

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .includingAll
        map.overrideUserInterfaceStyle = .dark
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.showsTraffic = surface.showsTraffic
        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)

        for pin in surface.pins {
            let a = MKPointAnnotation()
            a.coordinate = pin.coordinate
            a.title = pin.title
            map.addAnnotation(a)
        }
        if let poly = surface.routePolyline {
            map.addOverlay(poly, level: .aboveRoads)
        }

        let region = MKCoordinateRegion(
            center: surface.center,
            latitudinalMeters: surface.spanMeters,
            longitudinalMeters: surface.spanMeters
        )
        map.setRegion(region, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = UIColor(red: 0.72, green: 1.0, blue: 0.22, alpha: 0.95)
                r.lineWidth = 5
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Nawigacja: wymagany disclaimer (Program Agreement §3.3.F)

enum NavigationEULA {
    static let defaultsKey = "acceptedRealtimeNavEULA"

    /// Wymagany tekst EN z Apple Developer Program License Agreement.
    static let requiredNoticeEN = """
    YOUR USE OF THIS REAL TIME ROUTE GUIDANCE APPLICATION IS AT YOUR SOLE RISK. \
    LOCATION DATA MAY NOT BE ACCURATE.
    """

    static var isAccepted: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func accept() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }
}

struct NavigationEULASheet: View {
    var onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nawigacja w czasie rzeczywistym")
                        .font(.title2.bold())

                    Text("Drive Mate korzysta z Apple Maps (MapKit) oraz lokalizacji GPS do prowadzenia po trasie. Przed korzystaniem zaakceptuj poniższe warunki wymagane przez Apple:")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text(NavigationEULA.requiredNoticeEN)
                        .font(.system(.body, design: .monospaced))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        }

                    Text("Korzystanie z tej aplikacji do prowadzenia trasy w czasie rzeczywistym odbywa się wyłącznie na Twoje ryzyko. Dane lokalizacji mogą być niedokładne.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Mapy, miejsca i trasy pochodzą z Apple Maps. Szczegóły: apple.com/legal/internet-services/maps/")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Akceptuję") {
                        NavigationEULA.accept()
                        onAccept()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .presentationDetents([.medium, .large])
    }
}
