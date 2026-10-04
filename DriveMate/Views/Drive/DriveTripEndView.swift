import SwiftUI
import MapKit
import CoreLocation
import UIKit

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
    /// Dwie osobne animacje podsumowania.
    @State private var summaryAct: SummaryAct = .flag

    // Akt 1 — limonkowa flaga z autkiem
    @State private var flagScale: CGFloat = 0.08
    @State private var flagOpacity: Double = 1
    @State private var flagWaveActive = false

    // Akt 2 — kafelki (osobny bounce na każdy)
    @State private var showDistance = false
    @State private var showSpeed = false
    @State private var distanceScale: CGFloat = 0.92
    @State private var speedScale: CGFloat = 0.92
    @State private var summaryOpacity: Double = 1
    @State private var actionsAppear = false
    @State private var parkings: [ParkingOption] = []
    @State private var isSearchingParking = false
    @State private var parkingError: String?
    @State private var parkingAppear = false

    /// Retencja generatorów — lokalne obiekty bywają dealokowane zanim haptyka zdąży odpalić.
    private static let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private static let softHaptic = UIImpactFeedbackGenerator(style: .soft)
    private static let notifyHaptic = UINotificationFeedbackGenerator()

    private enum SummaryAct: Equatable {
        case flag
        case tiles
    }

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

    // MARK: - Summary (dwa akty animacji)

    private var summaryPhase: some View {
        ZStack {
            // AKT 1 — limonkowa flaga z autkiem
            if summaryAct == .flag {
                TripSummaryCarFlagView(waveActive: flagWaveActive)
                    .scaleEffect(flagScale)
                    .opacity(flagOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }

            // AKT 2 — kafelki
            if summaryAct == .tiles {
                VStack(spacing: 18) {
                    Text("Podsumowanie trasy")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .opacity(showDistance ? 1 : 0)
                        .padding(.top, 36)

                    Spacer(minLength: 0)

                    VStack(spacing: 16) {
                        summaryCard(
                            title: "Długość trasy",
                            value: summary.distanceLabel,
                            subtitle: "czas \(summary.durationLabel)",
                            visible: showDistance,
                            bounceScale: distanceScale
                        )

                        summaryCard(
                            title: "Średnia prędkość",
                            value: summary.averageSpeedLabel,
                            subtitle: summary.destinationTitle.map { "do: \($0)" } ?? "cała trasa",
                            visible: showSpeed,
                            bounceScale: speedScale
                        )
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
    }

    private func summaryCard(
        title: String,
        value: String,
        subtitle: String,
        visible: Bool,
        bounceScale: CGFloat
    ) -> some View {
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
                .stroke(
                    visible
                        ? DriveMatePalette.limeRoute.opacity(0.45)
                        : Color.white.opacity(0.18),
                    lineWidth: 0.9
                )
        }
        .scaleEffect(visible ? bounceScale : 0.88)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -120)
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
        Button {
            MechanicalClickSound.play()
            action()
        } label: {
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

    // MARK: - Sequence (akt 1: flaga → akt 2: kafelki)

    private func runSummarySequence() async {
        Self.heavyHaptic.prepare()
        Self.rigidHaptic.prepare()
        Self.softHaptic.prepare()
        Self.notifyHaptic.prepare()

        // ═══════════════════════════════════════
        // AKT 1 — limonkowa flaga z autkiem
        // ═══════════════════════════════════════
        summaryAct = .flag
        flagOpacity = 1
        flagScale = 0.08
        flagWaveActive = false

        // Krótka chwila na pojawienie się overlay — potem boom + spring
        try? await Task.sleep(nanoseconds: 120_000_000)

        flagWaveActive = true
        withAnimation(.spring(response: 0.48, dampingFraction: 0.52)) {
            flagScale = 1.14
        }
        // Mocna haptyka przez cały „wybuch” flagi (statyczne generatory = pewny trigger)
        fireFlagHaptics()

        try? await Task.sleep(nanoseconds: 420_000_000)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            flagScale = 1.0
        }

        // Flaga faluje — lekkie impulsy w rytmie
        for _ in 0..<4 {
            try? await Task.sleep(nanoseconds: 220_000_000)
            Self.softHaptic.impactOccurred(intensity: 0.55)
        }

        withAnimation(.easeIn(duration: 0.28)) {
            flagOpacity = 0
            flagScale = 1.18
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        flagWaveActive = false

        // ═══════════════════════════════════════
        // AKT 2 — kafelki (góra → bounce, dół → bounce)
        // ═══════════════════════════════════════
        withAnimation(.easeOut(duration: 0.12)) {
            summaryAct = .tiles
        }
        try? await Task.sleep(nanoseconds: 60_000_000)

        await bounceTileIn(which: .distance)
        try? await Task.sleep(nanoseconds: 280_000_000)
        await bounceTileIn(which: .speed)

        // Chwila na odczyt
        try? await Task.sleep(nanoseconds: 1_800_000_000)

        withAnimation(.easeInOut(duration: 0.4)) {
            summaryOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 420_000_000)
        phase = .actions
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
            actionsAppear = true
        }
    }

    private func fireFlagHaptics() {
        Self.rigidHaptic.prepare()
        Self.heavyHaptic.prepare()
        Self.notifyHaptic.prepare()

        Self.rigidHaptic.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Self.heavyHaptic.impactOccurred(intensity: 1.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            Self.heavyHaptic.impactOccurred(intensity: 1.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            Self.notifyHaptic.notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            Self.rigidHaptic.impactOccurred(intensity: 0.95)
        }
    }

    private enum BounceTile { case distance, speed }

    private func bounceTileIn(which: BounceTile) async {
        switch which {
        case .distance: distanceScale = 0.9
        case .speed: speedScale = 0.9
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
            switch which {
            case .distance:
                showDistance = true
                distanceScale = 1.1
            case .speed:
                showSpeed = true
                speedScale = 1.1
            }
        }
        Self.heavyHaptic.impactOccurred(intensity: 1.0)
        try? await Task.sleep(nanoseconds: 280_000_000)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
            switch which {
            case .distance: distanceScale = 1.0
            case .speed: speedScale = 1.0
            }
        }
        Self.softHaptic.impactOccurred(intensity: 0.7)
        try? await Task.sleep(nanoseconds: 220_000_000)
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

// MARK: - Limonkowa flaga z autkiem (powiększenie + falowanie)

private struct TripSummaryCarFlagView: View {
    var waveActive: Bool

    private var lime: Color { DriveMatePalette.limeRoute }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !waveActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wave = waveActive ? sin(t * 5.2) : 0
            let flutter = waveActive ? sin(t * 8.4 + 0.7) : 0

            ZStack {
                // Miękki blask
                Circle()
                    .fill(lime.opacity(0.14 + abs(wave) * 0.08))
                    .frame(width: 220, height: 220)
                    .blur(radius: 28)

                HStack(alignment: .bottom, spacing: 0) {
                    // Maszt
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.22)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 7, height: 168)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

                    // Płótno flagi — faluje od masztu
                    ZStack {
                        flagCloth(wave: CGFloat(wave), flutter: CGFloat(flutter))

                        Image(systemName: "car.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.78))
                            .offset(x: 4 + CGFloat(flutter) * 2, y: CGFloat(wave) * 2)
                    }
                    .frame(width: 118, height: 78)
                    .padding(.bottom, 78)
                    // Kotwica przy maszcie — prawa krawędź „macha”
                    .rotation3DEffect(
                        .degrees(wave * 14),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.45
                    )
                    .rotationEffect(.degrees(flutter * 3.2), anchor: .leading)
                    .offset(y: CGFloat(wave) * 3)
                }
                .shadow(color: lime.opacity(0.55), radius: 18, y: 0)
                .shadow(color: lime.opacity(0.28), radius: 36, y: 8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func flagCloth(wave: CGFloat, flutter: CGFloat) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))

            // Górna krawędź z falą
            let segments = 10
            for i in 1...segments {
                let x = w * CGFloat(i) / CGFloat(segments)
                let amp = (x / w) * 7
                let y = sin((x / w) * .pi * 1.6 + wave * 1.8) * amp
                    + flutter * amp * 0.35
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Prawa krawędź (lekko wcięta przy fali)
            let tipInset = 4 + abs(wave) * 3
            path.addLine(to: CGPoint(x: w - tipInset, y: h * 0.5 + flutter * 4))

            // Dolna krawędź z falą
            for i in (0..<segments).reversed() {
                let x = w * CGFloat(i) / CGFloat(segments)
                let amp = (x / w) * 7
                let y = h + sin((x / w) * .pi * 1.6 + wave * 1.8 + 0.4) * amp
                    - flutter * amp * 0.25
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.closeSubpath()

            ctx.fill(path, with: .color(lime.opacity(0.95)))
            ctx.stroke(
                path,
                with: .color(Color.white.opacity(0.28)),
                lineWidth: 1.2
            )

            // Delikatne fałdy
            for i in 1..<4 {
                let x = w * CGFloat(i) / 4.5
                var crease = Path()
                crease.move(to: CGPoint(x: x, y: 6))
                crease.addQuadCurve(
                    to: CGPoint(x: x + wave * 3, y: h - 6),
                    control: CGPoint(x: x + flutter * 5, y: h * 0.5)
                )
                ctx.stroke(crease, with: .color(Color.black.opacity(0.12)), lineWidth: 1)
            }
        }
    }
}

struct EndRouteButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            MechanicalClickSound.play()
            action()
        } label: {
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
