import SwiftUI

/// Poświata krawędzi ekranu w stylu Siri — lekka, jedna warstwa blura.
struct SiriEdgeGlowOverlay: View {
    var intensity: CGFloat

    @State private var spin: Double = 0

    private let palette: [Color] = [
        Color(red: 0.35, green: 0.75, blue: 1.0),
        Color(red: 0.55, green: 0.45, blue: 1.0),
        Color(red: 0.25, green: 0.55, blue: 1.0),
        Color(red: 0.45, green: 0.95, blue: 1.0),
        Color(red: 0.20, green: 0.40, blue: 0.95),
        Color(red: 0.70, green: 0.55, blue: 1.0),
        Color(red: 0.30, green: 0.85, blue: 1.0),
        Color(red: 0.35, green: 0.75, blue: 1.0)
    ]

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(
                cornerRadius: min(geo.size.width, geo.size.height) * 0.08,
                style: .continuous
            )

            ZStack {
                shape
                    .stroke(
                        AngularGradient(colors: palette, center: .center, angle: .degrees(spin)),
                        lineWidth: 18
                    )
                    .blur(radius: 16)

                shape
                    .stroke(
                        AngularGradient(
                            colors: palette.map { $0.opacity(0.9) },
                            center: .center,
                            angle: .degrees(spin * 1.1)
                        ),
                        lineWidth: 3
                    )
            }
            .padding(3)
            .frame(width: geo.size.width, height: geo.size.height)
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .opacity(Double(min(max(intensity, 0), 1)))
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                spin = 360
            }
        }
    }
}

/// Lekkie paski dyktafonu — TimelineView zamiast ciągłego re-layoutu SwiftUI.
struct VoiceWaveVisualizer: View {
    var level: CGFloat
    var barCount: Int = 24

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 6) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.92, blue: 1.0),
                                    Color(red: 0.25, green: 0.55, blue: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 5, height: barHeight(for: index, time: t))
                }
            }
            .frame(height: 110)
        }
        .drawingGroup()
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        let mid = CGFloat(barCount - 1) / 2
        let dist = abs(CGFloat(index) - mid) / max(mid, 1)
        let envelope = 1 - dist * 0.55
        let wave = sin(Double(index) * 0.55 + time * 5.2) * 0.5 + 0.5
        let chatter = sin(Double(index) * 1.25 - time * 8.0) * 0.5 + 0.5
        let lvl = max(Double(level), 0.05)
        let base: CGFloat = 10
        let amp = 16 + 78 * lvl * Double(envelope)
        return base + CGFloat(amp * (0.38 + 0.38 * wave + 0.24 * chatter * lvl))
    }
}

struct DictaphoneCircleButton: View {
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "waveform" : "mic.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.95, blue: 1.0),
                            Color(red: 0.35, green: 0.65, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 58, height: 58)
                .background {
                    Circle().fill(.ultraThinMaterial.opacity(0.55))
                }
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color(red: 0.4, green: 0.8, blue: 1.0).opacity(isActive ? 0.9 : 0.35),
                                    Color.white.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(
                    color: Color(red: 0.3, green: 0.75, blue: 1.0).opacity(isActive ? 0.45 : 0.2),
                    radius: isActive ? 10 : 6
                )
                .scaleEffect(isActive ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dyktafon")
    }
}
