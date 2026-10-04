import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Combine

struct SpeedBadge: View {
    let speedKmh: Int
    var isSpeeding: Bool = false
    var pulseScale: CGFloat = 1

    private var accent: Color {
        isSpeeding ? Color(red: 1.0, green: 0.12, blue: 0.14) : DriveMatePalette.neonGreen
    }
    private var accentMid: Color {
        isSpeeding ? Color(red: 0.92, green: 0.08, blue: 0.12) : DriveMatePalette.neonGreenMid
    }
    private var accentDeep: Color {
        isSpeeding ? Color(red: 0.55, green: 0.02, blue: 0.06) : DriveMatePalette.neonGreenDeep
    }
    private var valueColor: Color {
        isSpeeding ? Color(red: 1.0, green: 0.08, blue: 0.1) : Color.black.opacity(0.9)
    }
    private var unitColor: Color {
        isSpeeding ? Color(red: 0.95, green: 0.15, blue: 0.18) : Color.black.opacity(0.55)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(speedKmh)")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .monospacedDigit()
            Text("KM/H")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(unitColor)
                .tracking(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 108, minHeight: 64)
        .background {
            ZStack {
                // 60% regular liquid glass — słabsze niż pełne clear na innych kafelkach
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.clear)
                    .liquidGlassRect(cornerRadius: 18, .regular)
                    .opacity(0.60)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(isSpeeding ? 0.62 : 0.5),
                                accentMid.opacity(isSpeeding ? 0.4 : 0.28),
                                accentDeep.opacity(isSpeeding ? 0.28 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSpeeding ? accent.opacity(0.85) : Color.white.opacity(0.4),
                        lineWidth: isSpeeding ? 1.4 : 1
                    )
            }
            .shadow(color: accent.opacity(isSpeeding ? 0.55 : 0.32), radius: isSpeeding ? 12 : 8, y: 2)
        }
        .scaleEffect(pulseScale)
        .accessibilityLabel("Prędkość \(speedKmh) kilometrów na godzinę")
    }
}

struct ClockBadge: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "H:mm"
        return f.string(from: now)
    }

    var body: some View {
        Text(timeText)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.95))
            .monospacedDigit()
            .padding(.horizontal, 16)
            .frame(minWidth: 96, minHeight: 64)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .liquidGlassRect(cornerRadius: 18, .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    }
            }
            .onReceive(timer) { now = $0 }
            .accessibilityLabel("Godzina \(timeText)")
    }
}

struct MusicControlsBar: View {
    @ObservedObject var player: MusicPlayerService
    var hasTracks: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            metallicButton(systemName: "backward.fill", size: 32) {
                MechanicalClickSound.play()
                player.previous(andPlay: player.isPlaying)
            }
            Spacer(minLength: 0)
            metallicButton(systemName: player.isPlaying ? "pause.fill" : "play.fill", size: 40) {
                MechanicalClickSound.play()
                player.togglePlayPause()
            }
            Spacer(minLength: 0)
            metallicButton(systemName: "forward.fill", size: 32) {
                MechanicalClickSound.play()
                player.next(andPlay: player.isPlaying)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 20)
        .frame(maxWidth: 480)
        .frame(minHeight: 96)
        .liquidGlassRect(cornerRadius: 30, .clear.interactive())
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .opacity(hasTracks ? 1 : 0.75)
    }

    private func metallicButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 0.78), Color(white: 0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
                .frame(width: 68, height: 68)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasTracks)
    }
}

struct RecenterNavButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.94, blue: 1.0),
                            Color(red: 0.25, green: 0.7, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 44)
                .liquidGlassCircle(.clear.interactive())
                .overlay { Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.9) }
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 1).opacity(0.35), radius: 8)
        }
        .buttonStyle(.plain)
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.6)),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        )
    }
}

struct RecordingIndicatorDot: View {
    @State private var lit = true

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 18, height: 18)
            .shadow(color: .red.opacity(lit ? 0.9 : 0.25), radius: lit ? 10 : 3)
            .opacity(lit ? 1 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    lit = false
                }
            }
            .accessibilityLabel("Nagrywanie aktywne")
    }
}

struct DriveView: View {
    @ObservedObject var location: LocationSpeedService
    @ObservedObject var player: MusicPlayerService
    @ObservedObject var library: MusicLibraryService
    @ObservedObject var mapState: NavigationMapState
    @ObservedObject var assistant: DriveMateAssistant
    @ObservedObject var camera: CameraRecorderService
    @ObservedObject var recentPlaces: RecentPlacesStore
    @ObservedObject var settings: AppSettings
    var isDark: Bool
    var leadingChrome: CGFloat = 168

    @State private var isMusicBarVisible = false
    @State private var musicHideTask: Task<Void, Never>?
    @State private var tripSummary: TripSummary?
    @State private var idleVoiceMode = false
    @State private var isSpeeding = false
    @State private var speedPulseScale: CGFloat = 1
    @State private var lastSpeedWarningAt: Date?
    @State private var speedPulseTask: Task<Void, Never>?
    @ObservedObject private var mapCompliance = MapComplianceStore.shared
    @ObservedObject private var restaurantOffer = RestaurantOfferService.shared
    @ObservedObject private var gasOffer = GasStationOfferService.shared
    @ObservedObject private var infoCard = DriveInfoCardStore.shared
    @ObservedObject private var chromeVisibility = DriveChromeVisibilityStore.shared

    /// Szacowany limit (MapKit nie podaje znaku) — teren zabudowany.
    private let assumedSpeedLimitKmh = 50
    private let speedGraceKmh = 3

    private var isNavigating: Bool { mapState.isNavigating }
    private var showingTripEnd: Bool { tripSummary != nil }
    /// Pełny Drive Mate (nawigacja / asystent) — bez cyan gradientu.
    private var showNavDriveMate: Bool {
        !showingTripEnd
            && !idleVoiceMode
            && assistant.isAvatarVisible
            && !assistant.isWakeListening
    }
    /// Konfiguracja głosowa — same oczy w prawym górnym + poświata (Siri glow).
    private var showVoiceConfigEyes: Bool {
        !showingTripEnd && idleVoiceMode
    }
    private var showComplianceMap: Bool {
        // Bez mini-mapki przy konfiguracji trasy / wyborze celu — zostaw tylko podgląd korków.
        !isNavigating
            && !showingTripEnd
            && mapCompliance.surface?.showsTraffic == true
            && !restaurantOffer.isActive
            && !gasOffer.isActive
            && !infoCard.isActive
    }

    var body: some View {
        ZStack {
            if showingTripEnd, let tripSummary {
                DriveTripEndView(
                    summary: tripSummary,
                    leadingChrome: leadingChrome,
                    userCoordinate: location.coordinate,
                    onBackToMenu: {
                        mapCompliance.clear()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                            self.tripSummary = nil
                        }
                    },
                    onNavigateToParking: { parking in
                        Task { await startNavigationToParking(parking) }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(30)
            } else if isNavigating {
                MapDriveView(
                    location: location,
                    mapState: mapState,
                    isDark: isDark,
                    musicBarVisible: isMusicBarVisible,
                    leadingChrome: leadingChrome,
                    onUserInteraction: { revealMusicBar() }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else {
                DriveIdleSetupView(
                    location: location,
                    recent: recentPlaces,
                    assistant: assistant,
                    settings: settings,
                    leadingChrome: leadingChrome,
                    onNavigationStarted: {
                        idleVoiceMode = false
                        mapCompliance.clear()
                        assistant.dismissAvatar()
                        revealMusicBar()
                    },
                    onVoiceModeChanged: { active in
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                            idleVoiceMode = active
                        }
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity.combined(with: .scale(scale: 1.04))
                    )
                )
            }

            // Attachment 6 §2.4 — Map Data zawsze z widoczną mapą Apple
            if showComplianceMap, let surface = mapCompliance.surface {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        AppleMapDataPreview(surface: surface, height: showingTripEnd ? 150 : 128)
                            .frame(maxWidth: 320)
                            .padding(.leading, leadingChrome + 8)
                            .padding(.trailing, 28)
                            .padding(.bottom, idleVoiceMode ? 18 : 22)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(17)
                .allowsHitTesting(true)
            }

            // Nawigacja / asystent — sam Drive Mate (bez gradientu), wycentrowany
            if showNavDriveMate {
                VStack {
                    DriveMateAvatar(
                        isVisible: true,
                        mood: assistant.avatarMood,
                        speechGlow: 0,
                        eyesOnly: false,
                        eyesDelay: 0,
                        minimalStyle: true
                    )
                    .onTapGesture {
                        assistant.toggleListening()
                    }
                    .padding(.top, 6)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .zIndex(20)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(true)
            }

            // Konfiguracja głosowa — oczy w prawym górnym, spojrzenie w lewy dolny; poświata = Siri glow
            if showVoiceConfigEyes {
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        DriveMateAvatar(
                            isVisible: true,
                            mood: assistant.avatarMood,
                            speechGlow: max(assistant.speechGlow, assistant.audioLevel),
                            eyesOnly: true,
                            eyesDelay: 0.2,
                            gazeBottomLeft: true
                        )
                        .onTapGesture {
                            assistant.toggleListening()
                        }
                        .padding(.trailing, 36)
                        .padding(.top, 14)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .zIndex(20)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(true)
            }

            if isNavigating, !showingTripEnd {
                navigatingChrome
            } else if !showingTripEnd, !idleVoiceMode {
                VStack {
                    HStack {
                        Spacer()
                        DriveMatePanel(assistant: assistant, guidance: nil)
                            .padding(.trailing, 36)
                            .padding(.top, 12)
                    }
                    Spacer()
                }
                .zIndex(18)
            }

            // Oferta restauracji — środek ekranu
            if restaurantOffer.phase == .offering || restaurantOffer.phase == .awaitingVoiceConfirm,
               let offer = restaurantOffer.offer {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .zIndex(40)
                RestaurantOfferPopup(
                    offer: offer,
                    onConfirm: {
                        Task {
                            let outcome = await restaurantOffer.navigateToOfferIfConfirmed()
                            assistant.promptAndListen(outcome.reply)
                        }
                    },
                    onCancel: {
                        restaurantOffer.dismiss()
                        mapCompliance.clear()
                        if mapState.isNavigating {
                            assistant.promptAndListen("Anulowano. Kontynuujemy trasę.")
                        }
                    }
                )
                .padding(.leading, leadingChrome * 0.35)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(41)
            }

            // Oferta stacji paliw
            if gasOffer.phase == .offering || gasOffer.phase == .awaitingVoiceConfirm,
               let offer = gasOffer.offer {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .zIndex(40)
                GasStationOfferPopup(
                    offer: offer,
                    nearbySummary: gasOffer.nearbySummary,
                    onConfirm: {
                        Task {
                            let outcome = await gasOffer.navigateToOfferIfConfirmed()
                            assistant.promptAndListen(outcome.reply)
                        }
                    },
                    onCancel: {
                        gasOffer.dismiss()
                        mapCompliance.clear()
                        if mapState.isNavigating {
                            assistant.promptAndListen("Anulowano. Kontynuujemy trasę.")
                        }
                    }
                )
                .padding(.leading, leadingChrome * 0.35)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(41)
            }

            // Info: ulica / koszt paliwa (auto-zamknięcie po TTS)
            if let card = infoCard.card {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .zIndex(38)
                    .onTapGesture { infoCard.dismiss() }
                DriveInfoCardPopup(card: card)
                    .padding(.leading, leadingChrome * 0.35)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(39)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: isNavigating)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: isMusicBarVisible)
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: showingTripEnd)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: showNavDriveMate)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: showVoiceConfigEyes)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: restaurantOffer.phase)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: gasOffer.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: infoCard.isActive)
        .onChange(of: mapState.isNavigating) { _, navigating in
            if navigating {
                idleVoiceMode = false
                mapCompliance.clear()
                assistant.dismissAvatar()
                // Wake już działa w całej sekcji Drive — upewnij się, że jest włączony.
                assistant.setNavigationWakeListening(true)
                revealMusicBar()
                mapState.updateGuidance(userCoordinate: location.coordinate)
            } else {
                // Po zakończeniu trasy nadal słuchaj Hey Drive w Drive.
                assistant.setNavigationWakeListening(true)
                musicHideTask?.cancel()
                isMusicBarVisible = false
                isSpeeding = false
                speedPulseScale = 1
            }
        }
        .onChange(of: location.speedKmh) { _, speed in
            handleSpeedLimitMonitor(speedKmh: speed)
        }
        .animation(.easeInOut(duration: 0.22), value: isSpeeding)
        .onAppear {
            mapState.updateGuidance(userCoordinate: location.coordinate)
            assistant.setNavigationWakeListening(true)
        }
        .onDisappear {
            musicHideTask?.cancel()
            assistant.setNavigationWakeListening(false)
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            mapState.updateGuidance(userCoordinate: location.coordinate)
            mapState.trackTripProgress(userCoordinate: location.coordinate)
            if let coord = location.coordinate {
                DriveMateMemoryStore.shared.observeNavigationAdherence(
                    userCoordinate: coord,
                    route: mapState.route,
                    destinationTitle: mapState.destinationTitle,
                    destinationCoordinate: mapState.destinationCoordinate
                )
            }
        }
        .onChange(of: location.coordinate?.longitude) { _, _ in
            mapState.updateGuidance(userCoordinate: location.coordinate)
            mapState.trackTripProgress(userCoordinate: location.coordinate)
            if let coord = location.coordinate {
                DriveMateMemoryStore.shared.observeNavigationAdherence(
                    userCoordinate: coord,
                    route: mapState.route,
                    destinationTitle: mapState.destinationTitle,
                    destinationCoordinate: mapState.destinationCoordinate
                )
            }
        }
        .onChange(of: mapState.turnAnnouncement) { _, announcement in
            guard let announcement else { return }
            assistant.announceNavigation(announcement)
            mapState.consumeTurnAnnouncement()
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveMateDidCancelRoute)) { note in
            let duration = note.userInfo?["duration"] as? TimeInterval ?? 0
            let distance = note.userInfo?["distance"] as? CLLocationDistance ?? 0
            let avg = note.userInfo?["avgSpeed"] as? Double ?? 0
            let title = note.userInfo?["title"] as? String
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                tripSummary = TripSummary(
                    durationSeconds: duration,
                    distanceMeters: distance,
                    averageSpeedKmh: avg,
                    destinationTitle: title
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveMateDidNavigate)) { note in
            // Przywrócenie trasy / nowa nawigacja — nigdy nie zostawiaj ekranu podsumowania.
            if tripSummary != nil {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    tripSummary = nil
                }
            }
            if note.userInfo?["restoredRoute"] as? Bool == true {
                revealMusicBar()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveMateDidControlMusic)) { _ in
            revealMusicBar(holdSeconds: 5.5)
        }
    }

    @ViewBuilder
    private var navigatingChrome: some View {
        VStack {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    if chromeVisibility.isVisible(.speedometer) {
                        SpeedBadge(
                            speedKmh: location.speedKmh,
                            isSpeeding: isSpeeding,
                            pulseScale: speedPulseScale
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                    if chromeVisibility.isVisible(.clock) {
                        ClockBadge()
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                    if chromeVisibility.isVisible(.recording), camera.showsRecordingIndicator {
                        RecordingIndicatorDot()
                            .padding(.top, 6)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.leading, leadingChrome)
                .padding(.top, 20)
                .onTapGesture { revealMusicBar() }
                .animation(.easeInOut(duration: 0.25), value: camera.showsRecordingIndicator)
                .animation(.spring(response: 0.38, dampingFraction: 0.84), value: chromeVisibility.hidden)

                Spacer()
                DriveMatePanel(
                    assistant: assistant,
                    guidance: mapState.nextTurnGuidance
                )
                .padding(.trailing, 36)
                .padding(.top, 12)
            }

            Spacer()
        }
        .allowsHitTesting(true)

        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    if chromeVisibility.isVisible(.recenter), mapState.showRecenterButton {
                        RecenterNavButton {
                            revealMusicBar()
                            mapState.recenterOnUser()
                        }
                    }
                    EndRouteButton {
                        endRoute()
                    }
                }
                .padding(.trailing, 28)
                .padding(.bottom, isMusicBarVisible ? 118 : 22)
            }
        }
        .zIndex(15)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isMusicBarVisible)

        if isMusicBarVisible {
            VStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                MusicControlsBar(player: player, hasTracks: player.hasTracks || !library.tracks.isEmpty)
                    .padding(.leading, leadingChrome + 8)
                    .padding(.trailing, 36)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in revealMusicBar() }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .zIndex(12)
        }
    }

    private func endRoute() {
        musicHideTask?.cancel()
        isMusicBarVisible = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DriveMateMemoryStore.shared.notifyTripEnded(
            destinationTitle: mapState.destinationTitle,
            destinationCoordinate: mapState.destinationCoordinate,
            subtitle: mapState.statusBanner ?? ""
        )
        let summary = mapState.endTripAndSummarize()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            tripSummary = summary
        }
    }

    private func startNavigationToParking(_ parking: ParkingOption) async {
        do {
            _ = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: parking.coordinate.latitude,
                toLongitude: parking.coordinate.longitude,
                destinationName: parking.name
            )
            NotificationCenter.default.post(
                name: .driveMateDidNavigate,
                object: nil,
                userInfo: [
                    "title": parking.name,
                    "subtitle": parking.address,
                    "lat": parking.coordinate.latitude,
                    "lon": parking.coordinate.longitude,
                    "saveRecent": false
                ]
            )
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                tripSummary = nil
            }
            revealMusicBar()
        } catch NavigationError.disclaimerRequired {
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
        } catch {
            // Zostaw ekran parkingów — użytkownik może wybrać inny.
        }
    }

    private func revealMusicBar(holdSeconds: Double = 4.0) {
        guard mapState.isNavigating else { return }
        if !isMusicBarVisible {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                isMusicBarVisible = true
            }
        }
        musicHideTask?.cancel()
        let holdNs = UInt64(max(1.5, holdSeconds) * 1_000_000_000)
        musicHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: holdNs)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                isMusicBarVisible = false
            }
        }
    }

    private func handleSpeedLimitMonitor(speedKmh: Int) {
        guard isNavigating, !showingTripEnd else {
            if isSpeeding {
                isSpeeding = false
                speedPulseScale = 1
            }
            return
        }

        let over = speedKmh > assumedSpeedLimitKmh + speedGraceKmh
        let wasSpeeding = isSpeeding
        isSpeeding = over

        guard over else { return }

        // Puls przy wejściu w przekroczenie
        if !wasSpeeding {
            pulseSpeedBadge()
        }
        announceSlowDownIfNeeded()
    }

    private func pulseSpeedBadge() {
        speedPulseTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            speedPulseScale = 1.22
        }
        speedPulseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                speedPulseScale = 1.0
            }
        }
    }

    private func announceSlowDownIfNeeded() {
        let now = Date()
        if let last = lastSpeedWarningAt, now.timeIntervalSince(last) < 35 {
            return
        }
        lastSpeedWarningAt = now
        assistant.announceNavigation("Zwolnij trochę — jedziesz za szybko.")
    }
}
