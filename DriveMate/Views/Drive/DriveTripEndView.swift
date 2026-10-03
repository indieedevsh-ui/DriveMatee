import SwiftUI
import MapKit
import CoreLocation

/// Overlay po zakończeniu trasy: animowane podsumowanie → przyciski menu / parkingi.
struct DriveTripEndView: View {
    let summary: TripSummary
    var leadingChrome: CGFloat
    var userCoordinate: CLLocationCoordinate2D?
    var onBackToMenu: () -> Void
    var onNavigateToParking: (ParkingOption) -> Void

    enum Phase: Equatable {
        case summary
        case actions
        case parking
    }

    @State private var phase: Phase = .summary
    @State private var showDuration = false
    @State private var showSpeed = false
    @State private var summaryOpacity: Double = 1
    @State private var actionsAppear = false
    @State private var parkings: [ParkingOption] = []
    @State private var isSearchingParking = false
    @State private var parkingError: String?
    @State private var parkingAppear = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .summary:
                summaryPhase
                    .opacity(summaryOpacity)
            case .actions:
                actionsPhase
                    .scaleEffect(actionsAppear ? 1 : 0.85)
                    .opacity(actionsAppear ? 1 : 0)
            case .parking:
                parkingPhase
                    .scaleEffect(parkingAppear ? 1 : 0.92)
                    .opacity(parkingAppear ? 1 : 0)
            }
        }
        .padding(.leading, leadingChrome)
        .task { await runSummarySequence() }
    }

    // MARK: - Summary

    private var summaryPhase: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            Text("Podsumowanie trasy")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .opacity(showDuration ? 1 : 0)

            VStack(spacing: 18) {
                summaryCard(
                    title: "Czas przejazdu",
                    value: summary.durationLabel,
                    subtitle: "na dystansie \(summary.distanceLabel)",
                    visible: showDuration
                )

                summaryCard(
                    title: "Średnia prędkość",
                    value: summary.averageSpeedLabel,
                    subtitle: summary.destinationTitle.map { "do: \($0)" } ?? "cała trasa",
                    visible: showSpeed
                )
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 0)
        }
    }

    private func summaryCard(title: String, value: String, subtitle: String, visible: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .liquidGlassRect(cornerRadius: 24, .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
        }
        .scaleEffect(visible ? 1 : 0.72)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 24)
    }

    // MARK: - Actions

    private var actionsPhase: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            tripActionButton(
                title: "Wróć do menu",
                systemImage: "house.fill"
            ) {
                onBackToMenu()
            }

            tripActionButton(
                title: "Znajdź pobliskie parkingi",
                systemImage: "parkingsign.circle.fill"
            ) {
                Task { await searchParking() }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private func tripActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 22)
            .liquidGlassCapsule(.clear.interactive())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.9)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Parking

    private var parkingPhase: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Pobliskie parkingi")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("Wróć") {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        phase = .actions
                        actionsAppear = true
                        parkingAppear = false
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.top, 28)

            Text("Najpierw darmowe w 1 km, potem dalsze darmowe i tańsze płatne.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

            if isSearchingParking {
                Spacer()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("Szukam parkingów na mapie…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 10)
                Spacer()
            } else if let parkingError {
                Spacer()
                Text(parkingError)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(parkings) { parking in
                            Button {
                                onNavigateToParking(parking)
                            } label: {
                                parkingRow(parking)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.trailing, 28)
        .padding(.bottom, 20)
    }

    private func parkingRow(_ parking: ParkingOption) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(parking.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(parking.address)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Text(parking.reason)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(parking.distanceLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(parking.costHint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(parking.isFree ? DriveMatePalette.neonGreen : .white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(parking.isFree
                                  ? DriveMatePalette.neonGreen.opacity(0.18)
                                  : Color.white.opacity(0.08))
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .liquidGlassRect(cornerRadius: 18, .clear.interactive())
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
    }

    // MARK: - Sequence

    private func runSummarySequence() async {
        try? await Task.sleep(nanoseconds: 280_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            showDuration = true
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            showSpeed = true
        }
        // Obie informacje widoczne → 3 s, potem znikają
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation(.easeInOut(duration: 0.45)) {
            summaryOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 480_000_000)
        phase = .actions
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
            actionsAppear = true
        }
    }

    private func searchParking() async {
        guard let userCoordinate else {
            parkingError = "Brak lokalizacji — włącz GPS, aby szukać parkingów."
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                phase = .parking
                parkingAppear = true
                actionsAppear = false
            }
            return
        }

        isSearchingParking = true
        parkingError = nil
        parkings = []
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .parking
            parkingAppear = true
            actionsAppear = false
        }

        do {
            let results = try await ParkingSearchService.shared.findNearbyParking(near: userCoordinate)
            parkings = results
            if results.isEmpty {
                parkingError = "Nie znaleziono parkingów w okolicy."
            }
        } catch {
            parkingError = "Nie udało się wyszukać parkingów."
        }
        isSearchingParking = false
    }
}

struct EndRouteButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Zakończ trasę")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .liquidGlassCapsule(.clear.interactive())
                .overlay {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.red.opacity(0.35),
                                    Color.white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zakończ trasę")
    }
}
