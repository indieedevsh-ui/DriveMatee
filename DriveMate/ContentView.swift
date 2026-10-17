import SwiftUI
import UIKit
import CoreLocation

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @ObservedObject private var library = MusicLibraryService.shared
    @ObservedObject private var player = MusicPlayerService.shared
    @StateObject private var location = LocationSpeedService()
    @StateObject private var clips = ClipStorageService()
    @StateObject private var camera = CameraRecorderService()
    @StateObject private var mapState = NavigationMapState()
    @StateObject private var assistant = DriveMateAssistant()
    @StateObject private var recentPlaces = RecentPlacesStore()

    @State private var selectedTab: AppTab = .drive
    @State private var showNavEULA = !NavigationEULA.isAccepted

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let placement: SidebarPlacement = landscape ? .leading : .bottom
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

            ZStack {
                Group {
                    if selectedTab == .drive {
                        Color.black
                    } else {
                        settings.isDark ? Color.black : Color(white: 0.9)
                    }
                }
                .ignoresSafeArea()

                tabContent(leadingChrome: leadingChrome, bottomChrome: bottomChrome)
                    .ignoresSafeArea()

                // Sidebar: lewa (poziom) albo dół (pion) — automatycznie.
                Group {
                    if landscape {
                        HStack(spacing: 0) {
                            SidebarView(
                                selected: $selectedTab,
                                isDark: settings.isDark,
                                placement: .leading,
                                edgeSafe: edgeSafe
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
                                edgeSafe: edgeSafe
                            )
                        }
                    }
                }
                .ignoresSafeArea()
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: placement)

                SiriEdgeGlowOverlay(intensity: assistant.siriGlowIntensity)
                    .ignoresSafeArea()
                    .zIndex(100)
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
    private func tabContent(leadingChrome: CGFloat, bottomChrome: CGFloat) -> some View {
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
                bottomChrome: bottomChrome
            )
        case .recorder:
            RecorderView(
                camera: camera,
                clips: clips,
                settings: settings,
                isDark: settings.isDark
            )
            .padding(.bottom, bottomChrome)
        case .settings:
            SettingsView(
                settings: settings,
                library: library,
                player: player,
                clips: clips
            )
            .padding(.leading, bottomChrome > 0 ? 0 : max(0, leadingChrome - 12))
            .padding(.bottom, bottomChrome)
        }
    }
}

#Preview {
    ContentView()
}
