import SwiftUI
import UIKit
import MapKit
import CoreLocation

struct SpeedBadge: View {
    let speedKmh: Int

    var body: some View {
        Text("\(speedKmh)KM/H")
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.9))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .frame(minWidth: 88, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DriveMatePalette.neonGreen.opacity(0.5),
                                DriveMatePalette.neonGreenMid.opacity(0.28),
                                DriveMatePalette.neonGreenDeep.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .liquidGlassRect(cornerRadius: 16, .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    }
                    .shadow(color: DriveMatePalette.neonGreen.opacity(0.32), radius: 8, y: 2)
            }
            .accessibilityLabel("Prędkość \(speedKmh) kilometrów na godzinę")
    }
}

struct MusicControlsBar: View {
    @ObservedObject var player: MusicPlayerService
    var hasTracks: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            metallicButton(systemName: "backward.fill", size: 22) { player.previous() }
            Spacer(minLength: 0)
            metallicButton(systemName: player.isPlaying ? "pause.fill" : "play.fill", size: 28) {
                player.togglePlayPause()
            }
            Spacer(minLength: 0)
            metallicButton(systemName: "forward.fill", size: 22) { player.next() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: 380)
        .liquidGlassRect(cornerRadius: 24, .clear.interactive())
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                .frame(width: 48, height: 48)
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
    var isDark: Bool
    var leadingChrome: CGFloat = 168

    @State private var isMusicBarVisible = false
    @State private var musicHideTask: Task<Void, Never>?
    @State private var tripSummary: TripSummary?
    @State private var idleVoiceMode = false
    @ObservedObject private var mapCompliance = MapComplianceStore.shared
    @ObservedObject private var restaurantOffer = RestaurantOfferService.shared

    private var isNavigating: Bool { mapState.isNavigating }
    private var showingTripEnd: Bool { tripSummary != nil }
    private var showAvatarTopTrailing: Bool {
        !isNavigating && !showingTripEnd && (idleVoiceMode || assistant.isAvatarVisible)
    }
    private var showComplianceMap: Bool {
        !isNavigating && mapCompliance.surface != nil && !restaurantOffer.isActive
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
                    onUserInteraction: { revealMusicBar() }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else {
                DriveIdleSetupView(
                    location: location,
                    recent: recentPlaces,
                    assistant: assistant,
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

            // Same oczy w prawym górnym — tylko poza nawigacją
            if showAvatarTopTrailing {
                VStack {
                    HStack {
                        Spacer()
                        DriveMateAvatar(
                            isVisible: assistant.isAvatarVisible || idleVoiceMode,
                            mood: assistant.avatarMood,
                            speechGlow: max(assistant.speechGlow, assistant.audioLevel),
                            eyesOnly: true,
                            eyesDelay: 0.32
                        )
                        .padding(.trailing, 28)
                        .padding(.top, 10)
                        .onTapGesture {
                            assistant.toggleListening()
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .zIndex(20)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
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
                        if restaurantOffer.phase == .awaitingVoiceConfirm {
                            Task {
                                let outcome = await restaurantOffer.navigateToOfferIfConfirmed()
                                if outcome.started {
                                    assistant.promptAndListen(outcome.reply)
                                } else {
                                    assistant.promptAndListen(outcome.reply)
                                }
                            }
                        } else {
                            restaurantOffer.beginAwaitingVoiceConfirm()
                            assistant.promptAndListen(restaurantOffer.confirmationPrompt())
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
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: isNavigating)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: isMusicBarVisible)
        .animation(.spring(response: 0.48, dampingFraction: 0.86), value: showingTripEnd)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: showAvatarTopTrailing)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: restaurantOffer.phase)
        .onChange(of: mapState.isNavigating) { _, navigating in
            if navigating {
                idleVoiceMode = false
                mapCompliance.clear()
                assistant.dismissAvatar()
                assistant.setNavigationWakeListening(true)
                revealMusicBar()
                mapState.updateGuidance(userCoordinate: location.coordinate)
            } else {
                assistant.setNavigationWakeListening(false)
                musicHideTask?.cancel()
                isMusicBarVisible = false
            }
        }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            mapState.updateGuidance(userCoordinate: location.coordinate)
            mapState.trackTripProgress(userCoordinate: location.coordinate)
        }
        .onChange(of: location.coordinate?.longitude) { _, _ in
            mapState.updateGuidance(userCoordinate: location.coordinate)
            mapState.trackTripProgress(userCoordinate: location.coordinate)
        }
        .onChange(of: mapState.turnAnnouncement) { _, announcement in
            guard let announcement else { return }
            assistant.announceNavigation(announcement)
            mapState.consumeTurnAnnouncement()
        }
        .onAppear {
            mapState.updateGuidance(userCoordinate: location.coordinate)
        }
        .onDisappear {
            musicHideTask?.cancel()
        }
    }

    @ViewBuilder
    private var navigatingChrome: some View {
        VStack {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    SpeedBadge(speedKmh: location.speedKmh)
                    if camera.showsRecordingIndicator {
                        RecordingIndicatorDot()
                            .padding(.top, 6)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.leading, leadingChrome)
                .padding(.top, 20)
                .onTapGesture { revealMusicBar() }
                .animation(.easeInOut(duration: 0.25), value: camera.showsRecordingIndicator)

                Spacer()
                DriveMatePanel(
                    assistant: assistant,
                    guidance: mapState.nextTurnGuidance,
                    showNavDriveComposer: true
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
                    if mapState.showRecenterButton {
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
                .padding(.bottom, isMusicBarVisible ? 88 : 22)
            }
        }
        .zIndex(15)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: isMusicBarVisible)

        if isMusicBarVisible {
            VStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                MusicControlsBar(player: player, hasTracks: !library.tracks.isEmpty)
                    .padding(.leading, leadingChrome + 8)
                    .padding(.trailing, 40)
                    .padding(.bottom, 16)
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

    private func revealMusicBar() {
        guard mapState.isNavigating else { return }
        if !isMusicBarVisible {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                isMusicBarVisible = true
            }
        }
        musicHideTask?.cancel()
        musicHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                isMusicBarVisible = false
            }
        }
    }
}
