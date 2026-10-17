import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Combine

struct SpeedBadge: View {
    let speedKmh: Int
    var isSpeeding: Bool = false
    var pulseScale: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme

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
                        isSpeeding
                            ? accent.opacity(0.85)
                            : (colorScheme == .light ? Color.black.opacity(0.28) : Color.white.opacity(0.4)),
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isLight: Bool { colorScheme == .light }

    private var timeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "H:mm"
        return f.string(from: now)
    }

    var body: some View {
        Text(timeText)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(isLight ? Color.black.opacity(0.92) : Color.white.opacity(0.95))
            .monospacedDigit()
            .padding(.horizontal, 16)
            .frame(minWidth: 96, minHeight: 64)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(isLight ? 0.16 : 0.28))
                    .liquidGlassRect(cornerRadius: 18, .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.28),
                                lineWidth: 1
                            )
                    }
            }
            .onReceive(timer) { now = $0 }
            .accessibilityLabel("Godzina \(timeText)")
    }
}

struct MusicControlsBar: View {
    @ObservedObject var player: MusicPlayerService
    @ObservedObject var musicSource: MusicSourceController = .shared
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private var controlsEnabled: Bool { musicSource.controlsEnabled }
    private var playing: Bool { musicSource.isPlaying }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                metallicButton(systemName: "backward.fill", size: 32) {
                    MechanicalClickSound.play()
                    musicSource.uiPrevious()
                }
                Spacer(minLength: 0)
                metallicButton(systemName: playing ? "pause.fill" : "play.fill", size: 40) {
                    MechanicalClickSound.play()
                    musicSource.uiTogglePlayPause()
                }
                Spacer(minLength: 0)
                metallicButton(systemName: "forward.fill", size: 32) {
                    MechanicalClickSound.play()
                    musicSource.uiNext()
                }
                Spacer(minLength: 0)
            }

            if let message = musicSource.panelMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isLight ? Color.black.opacity(0.7) : Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .onAppear {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            musicSource.dismissPanelMessage()
                        }
                    }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 20)
        .frame(maxWidth: 480)
        .frame(minHeight: 96)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(isLight ? 0.14 : 0))
                .liquidGlassRect(cornerRadius: 30, .clear.interactive())
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isLight
                            ? [
                                Color.black.opacity(0.35),
                                Color.black.opacity(0.12),
                                Color.black.opacity(0.22)
                            ]
                            : [
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
        .shadow(color: .black.opacity(isLight ? 0.18 : 0.28), radius: 14, y: 6)
        .opacity(controlsEnabled ? 1 : 0.75)
        .onAppear { musicSource.syncPlayingState() }
        // `player` obserwowany, żeby lokalne isPlaying odświeżało pasek.
        .onChange(of: player.isPlaying) { _, _ in
            musicSource.syncPlayingState()
        }
    }

    private func metallicButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isLight
                            ? [Color.black, Color(white: 0.22), Color(white: 0.4)]
                            : [.white, Color(white: 0.78), Color(white: 0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(isLight ? 0.15 : 0.45), radius: 2, y: 2)
                .frame(width: 68, height: 68)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!controlsEnabled)
    }
}

struct RecenterNavButton: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isLight
                            ? [Color.black.opacity(0.9), Color(white: 0.25)]
                            : [
                                Color(red: 0.75, green: 0.94, blue: 1.0),
                                Color(red: 0.25, green: 0.7, blue: 1.0)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Color.black.opacity(isLight ? 0.14 : 0))
                        .liquidGlassCircle(.clear.interactive())
                }
                .overlay {
                    Circle().stroke(
                        isLight ? Color.black.opacity(0.25) : Color.white.opacity(0.3),
                        lineWidth: 0.9
                    )
                }
                .shadow(
                    color: isLight
                        ? Color.black.opacity(0.15)
                        : Color(red: 0.3, green: 0.8, blue: 1).opacity(0.35),
                    radius: 8
                )
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
    /// Tryb AR: tylna kamera zamiast mapy 2D.
    @State private var isARMode = false
    /// Przypomnienie skrętu na skrzyżowaniu (AR) — znika po 5 s.
    @State private var arIntersectionReminder: TurnDirection?
    @State private var arReminderShownFor: Set<UUID> = []
    @State private var arReminderTask: Task<Void, Never>?
    @ObservedObject private var mapCompliance = MapComplianceStore.shared
    @ObservedObject private var restaurantOffer = RestaurantOfferService.shared
    @ObservedObject private var storeOffer = StoreOfferService.shared
    @ObservedObject private var gasOffer = GasStationOfferService.shared
    @ObservedObject private var arrivalConfirm = ArrivalConfirmService.shared
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
                ZStack {
                    if isARMode {
                        DriveARNavView(
                            camera: camera,
                            guidance: mapState.nextTurnGuidance,
                            intersectionReminder: arIntersectionReminder,
                            leadingChrome: leadingChrome
                        )
                        .transition(.opacity)
                    } else {
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
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: isARMode)
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

            // Przycisk oczu / kafelek skrętu — tylko podczas nawigacji (prawy górny róg).
            if isNavigating, !showingTripEnd {
                navigatingChrome
            }

            // Dojazd do celu — ukończyć trasę?
            if arrivalConfirm.isPrompting {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .zIndex(42)
                ArrivalConfirmPopup(
                    destinationTitle: arrivalConfirm.destinationTitle ?? "cel",
                    onConfirm: {
                        arrivalConfirm.consumePromptForCompletion()
                        endRoute()
                        assistant.promptAndListen("Super — kończymy trasę.")
                    },
                    onCancel: {
                        arrivalConfirm.dismissKeepNavigating()
                        assistant.promptAndListen("OK, jedziemy dalej.")
                    }
                )
                .padding(.leading, leadingChrome * 0.35)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(43)
                .onAppear {
                    assistant.promptAndListen(arrivalConfirm.confirmationPrompt())
                }
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

            // Oferta sklepu
            if storeOffer.phase == .offering || storeOffer.phase == .awaitingVoiceConfirm,
               let offer = storeOffer.offer {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .zIndex(40)
                StoreOfferPopup(
                    offer: offer,
                    onConfirm: {
                        Task {
                            let outcome = await storeOffer.navigateToOfferIfConfirmed()
                            assistant.promptAndListen(outcome.reply)
                        }
                    },
                    onCancel: {
                        storeOffer.dismiss()
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
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: storeOffer.phase)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: gasOffer.phase)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: arrivalConfirm.isPrompting)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: infoCard.isActive)
        .onChange(of: mapState.isNavigating) { _, navigating in
            if navigating {
                idleVoiceMode = false
                mapCompliance.clear()
                assistant.dismissAvatar()
                arReminderShownFor = []
                arIntersectionReminder = nil
                arrivalConfirm.resetForNewTrip()
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
                exitARMode(stopCameraIfIdle: true)
                arrivalConfirm.resetForNewTrip()
            }
        }
        .onChange(of: mapState.nextTurnGuidance) { _, guidance in
            updateARIntersectionReminder(with: guidance)
        }
        .onChange(of: mapState.recenterRequestID) { _, _ in
            // Głosowe „wyśrodkuj” przy włączonym AR — wróć do mapy, żeby widać efekt.
            if isARMode {
                exitARMode(stopCameraIfIdle: true)
            }
        }
        .onChange(of: location.speedKmh) { _, speed in
            handleSpeedLimitMonitor(speedKmh: speed)
        }
        .animation(.easeInOut(duration: 0.22), value: isSpeeding)
        .onAppear {
            // Nie pokazuj asystenta przy samym wejściu na zakładkę — tylko po wywołaniu.
            assistant.ensureAvatarHiddenUnlessActive()
            mapState.updateGuidance(userCoordinate: location.coordinate)
            assistant.setNavigationWakeListening(true)
        }
        .onDisappear {
            musicHideTask?.cancel()
            assistant.ensureAvatarHiddenUnlessActive()
            assistant.setNavigationWakeListening(false)
            // Przy przejściu na Recorder / Settings nie przerywaj muzyki.
            MusicPlayerService.shared.ensurePlaybackSessionCompatible()
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            handleNavigationLocationTick()
        }
        .onChange(of: location.coordinate?.longitude) { _, _ in
            handleNavigationLocationTick()
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

                Spacer(minLength: 0)
                DriveMatePanel(
                    assistant: assistant,
                    guidance: mapState.nextTurnGuidance
                )
                .padding(.trailing, 36)
                .padding(.top, 14)
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.84),
                    value: mapState.nextTurnGuidance?.maneuverID
                )
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.84),
                    value: mapState.nextTurnGuidance == nil
                )
            }

            Spacer()
        }
        .allowsHitTesting(true)

        VStack {
            Spacer()
                .allowsHitTesting(false)
            HStack(alignment: .bottom) {
                Spacer()
                    .allowsHitTesting(false)
                VStack(alignment: .trailing, spacing: 12) {
                    ARNavButton(isActive: isARMode) {
                        revealMusicBar()
                        toggleARMode()
                    }
                    if !isARMode, chromeVisibility.isVisible(.recenter), mapState.showRecenterButton {
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
                MusicControlsBar(player: player)
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
            // Nad warstwą „Zakończ trasę”, żeby przyciski play/pauza dostawały dotyk.
            .zIndex(25)
        }
    }

    private func handleNavigationLocationTick() {
        mapState.updateGuidance(userCoordinate: location.coordinate)
        mapState.trackTripProgress(userCoordinate: location.coordinate)
        mapState.considerAutoReroute(userCoordinate: location.coordinate)
        arrivalConfirm.update(
            userCoordinate: location.coordinate,
            destinationCoordinate: mapState.destinationCoordinate,
            destinationTitle: mapState.destinationTitle,
            isNavigating: mapState.isNavigating
        )
        if let coord = location.coordinate {
            DriveMateMemoryStore.shared.observeNavigationAdherence(
                userCoordinate: coord,
                route: mapState.route,
                destinationTitle: mapState.destinationTitle,
                destinationCoordinate: mapState.destinationCoordinate
            )
        }
    }

    private func endRoute() {
        musicHideTask?.cancel()
        isMusicBarVisible = false
        exitARMode(stopCameraIfIdle: true)
        arrivalConfirm.resetForNewTrip()
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

    private func toggleARMode() {
        if isARMode {
            exitARMode(stopCameraIfIdle: true)
        } else {
            Task { await enterARMode() }
        }
    }

    private func enterARMode() async {
        await camera.requestAccessAndConfigure()
        guard camera.permissionGranted else {
            assistant.lastError = camera.lastError ?? "Brak dostępu do kamery."
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            isARMode = true
        }
        updateARIntersectionReminder(with: mapState.nextTurnGuidance)
    }

    private func exitARMode(stopCameraIfIdle: Bool) {
        arReminderTask?.cancel()
        arReminderTask = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            isARMode = false
            arIntersectionReminder = nil
        }
        if stopCameraIfIdle {
            camera.stopSession()
        }
    }

    /// Na skrzyżowaniu (≤ 40 m) pokaż symbol skrętu na 5 s — raz na manewr.
    private func updateARIntersectionReminder(with guidance: NextTurnGuidance?) {
        guard isARMode else { return }
        guard let guidance, guidance.isAtIntersectionForAR else { return }
        guard !arReminderShownFor.contains(guidance.maneuverID) else { return }

        arReminderShownFor.insert(guidance.maneuverID)
        arReminderTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            arIntersectionReminder = guidance.direction
        }
        arReminderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                arIntersectionReminder = nil
            }
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
