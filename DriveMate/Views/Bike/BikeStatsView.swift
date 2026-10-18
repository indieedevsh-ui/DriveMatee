import SwiftUI
import MapKit
import CoreLocation

/// Zakładka Stats w trybie rowerowym — tętno, średnia prędkość, wysokość, minimapa trasy.
struct BikeStatsView: View {
    @ObservedObject var location: LocationSpeedService
    @ObservedObject var mapState: NavigationMapState
    @ObservedObject var stats: BikeRideStatsService
    var isDark: Bool
    var leadingChrome: CGFloat = 0
    var topChrome: CGFloat = 0
    var bottomChrome: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            Group {
                if landscape {
                    landscapeLayout(availableHeight: geo.size.height)
                } else {
                    portraitLayout
                }
            }
        }
        .background((isDark ? Color.black : Color(white: 0.92)).ignoresSafeArea())
        .task {
            await stats.requestHealthAccess()
        }
        .onAppear {
            if mapState.isNavigating { stats.startTrackingRide() }
        }
        .onChange(of: mapState.isNavigating) { _, nav in
            if nav { stats.startTrackingRide() } else { stats.stopTrackingRide() }
        }
    }

    // MARK: - Portrait

    private var portraitLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock(compact: false)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(statItems) { item in
                        statTile(item, compact: false)
                    }
                }

                healthErrorIfNeeded

                routeCard(mapHeight: 180, compact: false)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20 + topChrome)
            .padding(.bottom, 28 + bottomChrome)
        }
    }

    // MARK: - Landscape

    private func landscapeLayout(availableHeight: CGFloat) -> some View {
        let hPad: CGFloat = 16
        let contentH = max(0, availableHeight - 20)

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                headerBlock(compact: true)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(statItems) { item in
                        statTile(item, compact: true)
                    }
                }

                healthErrorIfNeeded

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: contentH, alignment: .topLeading)

            routeCard(mapHeight: min(220, contentH - 8), compact: true)
                .frame(width: min(280, max(200, contentH * 0.85)))
                .frame(maxHeight: contentH)
        }
        .padding(.leading, max(12, leadingChrome))
        .padding(.trailing, hPad)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Shared pieces

    private func headerBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            Text("STATS")
                .font(.system(size: compact ? 22 : 28, weight: .bold, design: .rounded))
                .foregroundStyle(isDark ? .white : .black.opacity(0.9))

            if !compact {
                Text("Dane z Health / Apple Watch oraz GPS podczas jazdy.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDark ? .white.opacity(0.55) : .black.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var healthErrorIfNeeded: some View {
        if let err = stats.healthError {
            Text(err)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func routeCard(mapHeight: CGFloat, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text("Trasa")
                .font(.system(size: compact ? 13 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(isDark ? .white : .black.opacity(0.88))

            RouteShapeMiniMap(route: mapState.route, isDark: isDark)
                .frame(maxWidth: .infinity)
                .frame(height: mapHeight)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous))
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous)
                .fill(Color.black.opacity(isDark ? 0.35 : 0.06))
                .liquidGlassRect(cornerRadius: compact ? 18 : 24, .clear)
        }
    }

    private var statItems: [StatItem] {
        [
            StatItem(
                id: "hr",
                title: "Tętno",
                value: stats.heartRateBPM.map { "\($0)" } ?? "—",
                unit: "BPM",
                icon: "heart.fill",
                accent: Color(red: 1.0, green: 0.35, blue: 0.42)
            ),
            StatItem(
                id: "avg",
                title: "Śr. prędkość",
                value: stats.averageSpeedKmh > 0
                    ? String(format: "%.1f", stats.averageSpeedKmh)
                    : "—",
                unit: "KM/H",
                icon: "speedometer",
                accent: DriveMatePalette.limeRoute
            ),
            StatItem(
                id: "maxAlt",
                title: "Najwyżej",
                value: stats.maxAltitudeMeters > 0
                    ? String(format: "%.0f", stats.maxAltitudeMeters)
                    : "—",
                unit: "M N.P.M.",
                icon: "mountain.2.fill",
                accent: Color(red: 0.45, green: 0.75, blue: 1.0)
            ),
            StatItem(
                id: "nowAlt",
                title: "Teraz",
                value: location.altitudeMeters != 0
                    ? String(format: "%.0f", location.altitudeMeters)
                    : "—",
                unit: "M N.P.M.",
                icon: "arrow.up.and.down",
                accent: Color.white.opacity(0.7)
            )
        ]
    }

    private func statTile(_ item: StatItem, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: compact ? 12 : 17, weight: .semibold))
                    .foregroundStyle(item.accent)
                if compact {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isDark ? .white.opacity(0.55) : .black.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            if !compact {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDark ? .white.opacity(0.55) : .black.opacity(0.45))
            }
            Text(item.value)
                .font(.system(size: compact ? 22 : 32, weight: .black, design: .rounded))
                .foregroundStyle(isDark ? .white : .black.opacity(0.9))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(item.unit)
                .font(.system(size: compact ? 9 : 11, weight: .bold, design: .rounded))
                .foregroundStyle(item.accent.opacity(0.9))
                .tracking(0.6)
        }
        .padding(compact ? 10 : 16)
        .frame(maxWidth: .infinity, minHeight: compact ? 72 : 132, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous)
                .fill(Color.black.opacity(isDark ? 0.35 : 0.06))
                .liquidGlassRect(cornerRadius: compact ? 16 : 22, .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous)
                .stroke(Color.white.opacity(isDark ? 0.12 : 0.2), lineWidth: 0.8)
        }
    }
}

private struct StatItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let icon: String
    let accent: Color
}

/// Minimapa kształtu trasy (polyline).
struct RouteShapeMiniMap: View {
    var route: MKRoute?
    var isDark: Bool

    var body: some View {
        Group {
            if let route {
                Map(initialPosition: .region(region(for: route))) {
                    MapPolyline(route.polyline)
                        .stroke(DriveMatePalette.limeRoute, lineWidth: 4)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .disabled(true)
            } else {
                ZStack {
                    (isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
                    VStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(DriveMatePalette.limeRoute.opacity(0.7))
                        Text("Brak aktywnej trasy")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isDark ? .white.opacity(0.45) : .black.opacity(0.4))
                    }
                }
            }
        }
    }

    private func region(for route: MKRoute) -> MKCoordinateRegion {
        let rect = route.polyline.boundingMapRect
        var region = MKCoordinateRegion(rect)
        region.span.latitudeDelta *= 1.35
        region.span.longitudeDelta *= 1.35
        return region
    }
}
