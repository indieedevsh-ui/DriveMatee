import SwiftUI
import RiveRuntime

/// Fullscreen intro Rive przy skanie NFC / zmianie trybu.
struct TravelModeIntroOverlay: View {
    let mode: TravelMode
    var onFinished: () -> Void

    @StateObject private var rive: RiveViewModel
    @State private var appear = false

    init(mode: TravelMode, onFinished: @escaping () -> Void) {
        self.mode = mode
        self.onFinished = onFinished
        _rive = StateObject(
            wrappedValue: RiveViewModel(
                fileName: mode.riveFileName,
                stateMachineName: mode.riveStateMachineName,
                artboardName: mode.riveArtboardName
            )
        )
    }

    /// Identyczny gradient co artboard ModeBike / ModeCar (scene.rml Background).
    private var artboardGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Self.hex(0x0B, 0x12, 0x10), location: 0),
                .init(color: Self.hex(0x12, 0x20, 0x18), location: 0.55),
                .init(color: Self.hex(0x0A, 0x10, 0x0E), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func hex(_ r: Int, _ g: Int, _ b: Int) -> SwiftUI.Color {
        SwiftUI.Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    var body: some View {
        ZStack {
            // Pełny ekran = te same stopy co w Rive → brak „kwadratu” animacji.
            artboardGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                rive.view()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 560, maxHeight: 560)
                    .padding(.horizontal, 12)
                    .scaleEffect(appear ? 1 : 0.92)
                    .opacity(appear ? 1 : 0)

                AnimatedModeTitle(text: mode.title)
                    .padding(.horizontal, 24)
                    .opacity(appear ? 1 : 0)

                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                appear = true
            }
            Task { @MainActor in
                // Wystarczy na wolniejszą falę liter + pełną poświatę.
                try? await Task.sleep(nanoseconds: 4_200_000_000)
                withAnimation(.easeOut(duration: 0.4)) {
                    appear = false
                }
                try? await Task.sleep(nanoseconds: 380_000_000)
                onFinished()
            }
        }
    }
}

/// Literki L→P: ciemnozielony tekst + limonkowa poświata przechodząca przez napis.
private struct AnimatedModeTitle: View {
    let text: String
    @State private var revealedCount = 0
    @State private var settled = false
    /// Pozycja środka limonkowej poświaty w przestrzeni 0…1 (leading→trailing).
    @State private var glowX: CGFloat = -0.45

    /// Ciemna zieleń z artboardu (#1F3D24).
    private let ink = SwiftUI.Color(red: 0x1F / 255, green: 0x3D / 255, blue: 0x24 / 255)
    /// Limonka z animacji (#B2FF59).
    private let lime = SwiftUI.Color(red: 0xB2 / 255, green: 0xFF / 255, blue: 0x59 / 255)

    private var titleFont: SwiftUI.Font {
        .system(size: 30, weight: .bold, design: .rounded)
    }

    var body: some View {
        Group {
            if settled {
                // Jedyna limonkowa poświata — po pełnym ujawnieniu ciemnozielonego tekstu.
                GlowSweepTitle(text: text, glowX: glowX, ink: ink, lime: lime, font: titleFont)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                        let on = index < revealedCount
                        Text(char == " " ? "\u{00A0}" : String(char))
                            .font(titleFont)
                            .foregroundStyle(ink)
                            .opacity(on ? 1 : 0)
                            .scaleEffect(on ? 1.0 : 0.88, anchor: .center)
                            .offset(y: on ? 0 : 6)
                            .animation(.spring(response: 0.52, dampingFraction: 0.82), value: on)
                    }
                }
            }
        }
        .accessibilityLabel(text)
        .task {
            revealedCount = 0
            settled = false
            glowX = -0.45
            try? await Task.sleep(nanoseconds: 260_000_000)
            let stepNs: UInt64 = 58_000_000
            for i in 1...max(text.count, 1) {
                guard !Task.isCancelled else { return }
                revealedCount = i
                try? await Task.sleep(nanoseconds: stepNs)
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            settled = true
            // Jedna poświata L→P (bez wcześniejszej fali limonki na literkach).
            glowX = -0.45
            withAnimation(.easeInOut(duration: 2.05)) {
                glowX = 1.45
            }
        }
    }
}

/// Poświata z `Animatable` — płynna interpolacja pozycji gradientu.
private struct GlowSweepTitle: View, Animatable {
    let text: String
    var glowX: CGFloat
    let ink: SwiftUI.Color
    let lime: SwiftUI.Color
    let font: SwiftUI.Font

    var animatableData: CGFloat {
        get { glowX }
        set { glowX = newValue }
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(ink)
            .overlay {
                Text(text)
                    .font(font)
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: lime.opacity(0.08), location: 0.28),
                                .init(color: lime.opacity(0.55), location: 0.42),
                                .init(color: lime, location: 0.5),
                                .init(color: lime.opacity(0.55), location: 0.58),
                                .init(color: lime.opacity(0.08), location: 0.72),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: UnitPoint(x: glowX - 0.55, y: 0.5),
                            endPoint: UnitPoint(x: glowX + 0.55, y: 0.5)
                        )
                    )
                    .shadow(color: lime.opacity(0.55), radius: 14, y: 0)
                    .shadow(color: lime.opacity(0.28), radius: 26, y: 0)
                    .transaction { $0.animation = nil }
            }
            .mask(Text(text).font(font))
            .multilineTextAlignment(.center)
    }
}
