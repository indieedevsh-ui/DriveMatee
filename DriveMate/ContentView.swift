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
            let islandPad = landscape ? max(geo.safeAreaInsets.leading, 47) : max(geo.safeAreaInsets.leading, 12)
            let sidebarWidth = islandPad + 108 + 22

            ZStack {
                Group {
                    if selectedTab == .drive {
                        Color.black
                    } else {
                        settings.isDark ? Color.black : Color(white: 0.9)
                    }
                }
                .ignoresSafeArea()

                tabContent(sidebarWidth: sidebarWidth)
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    SidebarView(
                        selected: $selectedTab,
                        isDark: settings.isDark,
                        leadingSafe: islandPad
                    )

                    Spacer(minLength: 0)

                    if selectedTab == .drive && landscape && mapState.isNavigating {
                        RightGlassEdge()
                    }
                }
                .ignoresSafeArea()

                // Poświata Siri — cała aplikacja, płynne pojawianie przy dyktafonie / słuchaniu
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
            // Nie zapisuj parkingów z „Znajdź pobliskie parkingi” — tylko cele wpisane / wybrane świadomie.
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
            if tab == .recorder, settings.recorderEnabled {
                Task { await camera.requestAccessAndConfigure() }
            } else if tab != .recorder {
                // Nie zatrzymuj sesji gdy trwa ciągłe nagrywanie — działa w tle na Drive.
                if !camera.isContinuousRecording {
                    camera.stopSession()
                }
            }
        }
        .onAppear {
            MechanicalClickSound.prepare()
        }
    }

    @ViewBuilder
    private func tabContent(sidebarWidth: CGFloat) -> some View {
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
                leadingChrome: sidebarWidth + 12
            )
        case .recorder:
            RecorderView(
                camera: camera,
                clips: clips,
                settings: settings,
                isDark: settings.isDark
            )
            .padding(.leading, sidebarWidth)
        case .settings:
            SettingsView(
                settings: settings,
                library: library,
                player: player,
                clips: clips
            )
            .padding(.leading, sidebarWidth)
        }
    }
}

#Preview {
    ContentView()
}
