import SwiftUI
import UIKit
import CoreLocation

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @ObservedObject private var library = MusicLibraryService.shared
    @ObservedObject private var player = MusicPlayerService.shared
    @ObservedObject private var nfc = NFCModeService.shared
    @StateObject private var location = LocationSpeedService()
    @StateObject private var clips = ClipStorageService()
    @StateObject private var camera = CameraRecorderService()
    @StateObject private var mapState = NavigationMapState()
    @StateObject private var assistant = DriveMateAssistant()
    @StateObject private var recentPlaces = RecentPlacesStore()
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var bikeStats = BikeRideStatsService.shared
    @State private var selectedTab: AppTab = .drive
    @State private var showNavEULA = !NavigationEULA.isAccepted
    @State private var travelModeIntro: TravelMode?
    @State private var travelModeIntroToken = UUID()

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let placement: SidebarPlacement = landscape ? .leading : .bottom
            let visibleTabs = AppTab.visibleTabs(for: settings.travelMode)
            let edgeSafe: CGFloat = {
                if landscape {
                    return max(geo.safeAreaInsets.leading, 47)
                }
                return max(geo.safeAreaInsets.bottom, 12)
            }()
            let leadingChrome: CGFloat = landscape
                ? SidebarView.leadingWidth(edgeSafe: edgeSafe) + 12
                : 16
            let bottomChrome: CGFloat = landscape
                ? 0
                : SidebarView.bottomHeight(edgeSafe: edgeSafe)
            /// Portrait: odsunięcie od Dynamic Island / notch (status bar jest ukryty + ignoresSafeArea).
            let topChrome: CGFloat = landscape
                ? 0
                : max(geo.safeAreaInsets.top, 54) + 10

            ZStack {
                Group {
                    if selectedTab == .drive {
                        Color.black
                    } else {
                        settings.isDark ? Color.black : Color(white: 0.9)
                    }
                }
                .ignoresSafeArea()

                tabContent(
                    leadingChrome: leadingChrome,
                    bottomChrome: bottomChrome,
                    topChrome: topChrome
                )
                    .ignoresSafeArea()

                // Sidebar: lewa (poziom) albo dół (pion) — automatycznie.
                Group {
                    if landscape {
                        HStack(spacing: 0) {
                            SidebarView(
                                selected: $selectedTab,
                                isDark: settings.isDark,
                                placement: .leading,
                                edgeSafe: edgeSafe,
                                tabs: visibleTabs
                            )
                            Spacer(minLength: 0)
                            if selectedTab == .drive && mapState.isNavigating {
                                RightGlassEdge()
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            SidebarView(
                                selected: $selectedTab,
                                isDark: settings.isDark,
                                placement: .bottom,
                                edgeSafe: edgeSafe,
                                tabs: visibleTabs
                            )
                        }
                    }
                }
                .ignoresSafeArea()
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: placement)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: settings.travelMode)

                SiriEdgeGlowOverlay(intensity: assistant.siriGlowIntensity)
                    .ignoresSafeArea()
                    .zIndex(100)

                nfcOverlays
                    .animation(.spring(response: 0.45, dampingFraction: 0.84), value: nfc.pendingEmptyTagEncode)
                    .animation(.spring(response: 0.45, dampingFraction: 0.84), value: nfc.presentedModeToast)

                if let travelModeIntro {
                    TravelModeIntroOverlay(mode: travelModeIntro) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            self.travelModeIntro = nil
                        }
                    }
                    .id(travelModeIntroToken)
                    .transition(.opacity)
                    .zIndex(120)
                }
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showNavEULA) {
            NavigationEULASheet {
                showNavEULA = false
            }
        }
        .onChange(of: nfc.modeScanEpoch) { _, _ in
            guard let mode = nfc.lastScannedMode else { return }
            settings.travelMode = mode
            selectedTab = .drive
            // Za każdym skanem NFC — pełna animacja trybu (nawet przy tym samym trybie).
            travelModeIntroToken = UUID()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                travelModeIntro = mode
            }
        }
        .onChange(of: settings.travelMode) { old, mode in
            let tabs = AppTab.visibleTabs(for: mode)
            if !tabs.contains(selectedTab) {
                selectedTab = .drive
            }
            // Intro poza NFC tylko przy realnej zmianie trybu (np. z Ustawień).
            guard old != mode, nfc.presentedModeToast == nil else { return }
            travelModeIntroToken = UUID()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                travelModeIntro = mode
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                nfc.stopListening()
            }
        }
        .onOpenURL { url in
            nfc.handleOpenURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            nfc.handleUserActivity(activity)
        }
        .onAppear {
            player.bind(library: library)
            player.volume = Float(settings.musicVolume)
            settings.volumeDidChange = { [weak player] value in
                player?.volume = Float(value)
            }
            camera.bind(storage: clips)
            location.requestAccessAndStart()
            assistant.configure(
                settings: settings,
                music: player,
                navigation: MapKitNavigationService.shared,
                location: location,
                mapState: mapState
            )
            DriveVoiceUIBridge.shared.bind(
                camera: camera,
                settings: settings,
                music: player
            )
            DriveMateSiriBridge.flushPendingIfReady()
            if !NavigationEULA.isAccepted {
                showNavEULA = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveMateNeedsNavEULA)) { _ in
            showNavEULA = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveMateDidNavigate)) { note in
            if let saveRecent = note.userInfo?["saveRecent"] as? Bool, saveRecent == false {
                return
            }
            guard let info = note.userInfo,
                  let title = info["title"] as? String,
                  let lat = info["lat"] as? Double,
                  let lon = info["lon"] as? Double else { return }
            let subtitle = info["subtitle"] as? String ?? ""
            recentPlaces.add(
                title: title,
                subtitle: subtitle,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
        .onChange(of: selectedTab) { _, tab in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            MusicPlayerService.shared.ensurePlaybackSessionCompatible()
            if tab == .recorder, settings.recorderEnabled {
                Task { await camera.requestAccessAndConfigure() }
            } else if tab != .recorder {
                if !camera.isContinuousRecording {
                    camera.stopSession()
                }
            }
            if tab == .drive {
                assistant.ensureAvatarHiddenUnlessActive()
            }
        }
        .onAppear {
            MechanicalClickSound.prepare()
        }
    }

    @ViewBuilder
    private var nfcOverlays: some View {
        if nfc.pendingEmptyTagEncode {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(110)
                .onTapGesture {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        nfc.cancelEncodePrompt()
                    }
                }

            NFCEncodeTagSheet(
                onSelect: { mode in
                    settings.travelMode = mode
                    nfc.encodeEmptyTag(as: mode)
                },
                onCancel: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        nfc.cancelEncodePrompt()
                    }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
            .zIndex(111)
        }

        // Toast tylko gdy nie ma fullscreen Rive (unikamy podwójnego UI).
        if let mode = nfc.presentedModeToast, travelModeIntro == nil {
            VStack {
                Spacer(minLength: 0)
                NFCTravelModeToast(mode: mode)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92)),
                    removal: .opacity.combined(with: .scale(scale: 1.04))
                )
            )
            .zIndex(112)
        }
    }

    @ViewBuilder
    private func tabContent(
        leadingChrome: CGFloat,
        bottomChrome: CGFloat,
        topChrome: CGFloat
    ) -> some View {
        switch selectedTab {
        case .drive:
            DriveView(
                location: location,
                player: player,
                library: library,
                mapState: mapState,
                assistant: assistant,
                camera: camera,
                recentPlaces: recentPlaces,
                settings: settings,
                isDark: settings.isDark,
                leadingChrome: leadingChrome,
                bottomChrome: bottomChrome,
                topChrome: topChrome
            )
        case .recorder:
            RecorderView(
                camera: camera,
                clips: clips,
                settings: settings,
                isDark: settings.isDark,
                topChrome: topChrome
            )
            .padding(.bottom, bottomChrome)
        case .stats:
            BikeStatsView(
                location: location,
                mapState: mapState,
                stats: bikeStats,
                isDark: settings.isDark,
                leadingChrome: leadingChrome,
                topChrome: topChrome,
                bottomChrome: bottomChrome
            )
        case .settings:
            SettingsView(
                settings: settings,
                library: library,
                player: player,
                clips: clips
            )
            .padding(.leading, bottomChrome > 0 ? 0 : max(0, leadingChrome - 12))
            .padding(.top, topChrome > 0 ? topChrome : 0)
            .padding(.bottom, bottomChrome)
        }
    }
}

#Preview {
    ContentView()
}
