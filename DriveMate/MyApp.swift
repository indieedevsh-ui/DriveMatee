import SwiftUI
import AppIntents

@main
struct MyApp: App {
    @State private var showSplash = true

    init() {
        // Odśwież frazy Siri po starcie (dom / praca / własne miejsca).
        DriveMateAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                if showSplash {
                    DriveLoadingSplashView {
                        withAnimation(.easeOut(duration: 0.35)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
        }
    }
}
