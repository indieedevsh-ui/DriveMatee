import SwiftUI
import MapKit

/// Okienko: wybierz obszar mapy offline (domyślnie 10 km wokół GPS).
struct OfflineMapDownloadPromptView: View {
    @ObservedObject var store: OfflineMapPromptStore
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("MAPY OFFLINE")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DriveMatePalette.limeRoute)

                Text("Obszar do zapisania")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Domyślnie 10 km od Twojej pozycji. Po zatwierdzeniu pobieranie idzie w tle — możesz jeździć.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                OfflineMapRegionPicker(
                    center: $store.center,
                    radiusMeters: $store.radiusMeters
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }

                HStack {
                    Text(String(format: "Promień %.0f km", store.radiusMeters / 1000))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }

                Slider(
                    value: Binding(
                        get: { store.radiusMeters },
                        set: { store.radiusMeters = $0 }
                    ),
                    in: 5_000...25_000,
                    step: 1_000
                )
                .tint(DriveMatePalette.limeRoute)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Anuluj")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white.opacity(0.85))
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            }
                    }
                    Button(action: onConfirm) {
                        Text("Pobierz")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.black)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(DriveMatePalette.limeRoute)
                            }
                    }
                }
            }
            .padding(22)
        }
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.clear)
                .background {
                    LiquidGlassBackground(style: .regular, cornerRadius: 28)
                }
        }
        .padding(.horizontal, 20)
    }
}

private struct OfflineMapRegionPicker: UIViewRepresentable {
    @Binding var center: CLLocationCoordinate2D
    @Binding var radiusMeters: CLLocationDistance

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = true
        context.coordinator.circle = MKCircle(center: center, radius: radiusMeters)
        if let circle = context.coordinator.circle {
            map.addOverlay(circle)
        }
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 2.4,
            longitudinalMeters: radiusMeters * 2.4
        )
        map.setRegion(region, animated: false)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didPan(_:)))
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if let old = context.coordinator.circle {
            map.removeOverlay(old)
        }
        let circle = MKCircle(center: center, radius: radiusMeters)
        context.coordinator.circle = circle
        map.addOverlay(circle)
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 2.4,
            longitudinalMeters: radiusMeters * 2.4
        )
        if abs(map.region.center.latitude - center.latitude) > 0.0008
            || abs(map.region.span.latitudeDelta - region.span.latitudeDelta) > 0.02 {
            map.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: OfflineMapRegionPicker
        var circle: MKCircle?

        init(_ parent: OfflineMapRegionPicker) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: circle)
                r.fillColor = DriveMatePalette.limeRouteUI.withAlphaComponent(0.18)
                r.strokeColor = DriveMatePalette.limeRouteUI
                r.lineWidth = 2
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        @objc func didPan(_ g: UIPanGestureRecognizer) {
            guard g.state == .ended || g.state == .changed,
                  let map = g.view as? MKMapView else { return }
            parent.center = map.centerCoordinate
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

/// Małe kółeczko % podczas jazdy.
struct OfflineMapProgressBadge: View {
    @ObservedObject var service = OfflineMapDownloadService.shared

    var body: some View {
        if service.showsDriveBadge {
            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 46, height: 46)
                    .background {
                        LiquidGlassBackground(style: .regular, cornerRadius: 23)
                    }
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3)
                    .frame(width: 38, height: 38)
                Circle()
                    .trim(from: 0, to: max(0.02, service.progress))
                    .stroke(DriveMatePalette.limeRoute, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 38, height: 38)
                Text("\(service.progressPercent)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Pobieranie map offline \(service.progressPercent) procent")
        }
    }
}
