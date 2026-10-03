import SwiftUI
import UIKit

/// Clear liquid glass — pastylka (UIGlassEffect.clear) z opcjonalnym niebieskim podświetleniem.
struct ClearLiquidGlass: UIViewRepresentable {
    var blueIntensity: CGFloat = 0

    func makeUIView(context: Context) -> ClearGlassView { ClearGlassView() }

    func updateUIView(_ uiView: ClearGlassView, context: Context) {
        uiView.setBlueIntensity(blueIntensity)
    }
}

final class ClearGlassView: UIView {
    private let glassView: UIVisualEffectView
    private let tintView = UIView()
    private let rimView = UIView()
    private var blueIntensity: CGFloat = 0

    override init(frame: CGRect) {
        let effect = UIGlassEffect(style: .clear)
        glassView = UIVisualEffectView(effect: effect)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true

        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = UIColor(red: 0.55, green: 0.92, blue: 1.0, alpha: 0.10)
        addSubview(tintView)

        rimView.translatesAutoresizingMaskIntoConstraints = false
        rimView.backgroundColor = .clear
        rimView.layer.borderWidth = 1.5
        rimView.layer.borderColor = UIColor(red: 0.78, green: 0.96, blue: 1.0, alpha: 0.8).cgColor
        addSubview(rimView)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rimView.topAnchor.constraint(equalTo: topAnchor),
            rimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rimView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyBlueTint()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBlueIntensity(_ value: CGFloat) {
        let clamped = min(max(value, 0), 1)
        guard abs(clamped - blueIntensity) > 0.01 else { return }
        blueIntensity = clamped
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.applyBlueTint()
        }
    }

    private func applyBlueTint() {
        let t = blueIntensity
        let effect = UIGlassEffect(style: .clear)
        effect.tintColor = UIColor(
            red: 0.35 + 0.15 * (1 - t),
            green: 0.78 + 0.12 * (1 - t),
            blue: 1.0,
            alpha: 0.15 + 0.55 * t
        )
        glassView.effect = effect
        tintView.backgroundColor = UIColor(red: 0.40, green: 0.85, blue: 1.0, alpha: 0.08 + 0.42 * t)
        rimView.layer.borderColor = UIColor(
            red: 0.70 + 0.1 * t,
            green: 0.92,
            blue: 1.0,
            alpha: 0.75 + 0.2 * t
        ).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = min(bounds.width, bounds.height) / 2
        layer.cornerRadius = r
        glassView.layer.cornerRadius = r
        glassView.clipsToBounds = true
        rimView.layer.cornerRadius = r
        rimView.clipsToBounds = true
    }
}

/// Drive Mate — pastylka (capsule) liquid glass clear, albo same oczy.
struct DriveMateAvatar: View {
    var isVisible: Bool
    var mood: DriveMateAvatarMood = .idle
    /// 0…1 — niebieskie podświetlenie gdy AI wykrywa mowę.
    var speechGlow: CGFloat = 0
    /// Tylko oczy — bez ciałka i miny (tryb dyktafonu / Siri).
    var eyesOnly: Bool = false
    /// Opóźnienie pojawienia oczu po starcie poświaty (sekundy).
    var eyesDelay: Double = 0.32

    @State private var appearProgress: CGFloat = 0
    @State private var eyesProgress: CGFloat = 0
    @State private var blinkScale: CGFloat = 1
    @State private var lookOffset: CGFloat = 0
    @State private var pulseGlow: CGFloat = 0.55
    @State private var blinkTask: Task<Void, Never>?
    @State private var lookTask: Task<Void, Never>?
    @State private var eyesDelayTask: Task<Void, Never>?

    private let headWidth: CGFloat = 200
    private let headHeight: CGFloat = 118

    private let eyeTop = Color(red: 0.35, green: 0.72, blue: 0.98)
    private let eyeBottom = Color(red: 0.15, green: 0.48, blue: 0.88)
    private let cyanGlow = Color(red: 0.55, green: 0.94, blue: 1.0)

    var body: some View {
        Group {
            if eyesOnly {
                eyesOnlyBody
            } else {
                fullBody
            }
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                present(visible: true)
            } else {
                present(visible: false)
            }
        }
        .onAppear {
            if isVisible { present(visible: true) }
        }
        .onDisappear {
            stopIdleMotion()
            eyesDelayTask?.cancel()
        }
        .accessibilityLabel("Drive Mate")
    }

    private var eyesOnlyBody: some View {
        HStack(spacing: 18) {
            eye
            eye
        }
        .offset(x: lookOffset)
        .scaleEffect(y: blinkScale, anchor: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .scaleEffect(0.55 + 0.45 * eyesProgress)
        .opacity(Double(eyesProgress))
        .offset(y: (1 - eyesProgress) * -18)
        .shadow(color: cyanGlow.opacity(0.35 + 0.4 * speechGlow), radius: 10 + 6 * speechGlow)
        .animation(.easeInOut(duration: 0.28), value: speechGlow)
    }

    private var fullBody: some View {
        let hear = speechGlow
        return ZStack {
            Capsule(style: .continuous)
                .fill(cyanGlow.opacity((0.18 + 0.35 * hear) * pulseGlow))
                .blur(radius: 14 + 6 * hear)
                .scaleEffect(1.06 + 0.04 * hear)

            Capsule(style: .continuous)
                .fill(.clear)
                .background {
                    ClearLiquidGlass(blueIntensity: hear)
                        .clipShape(Capsule(style: .continuous))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.45, green: 0.88, blue: 1.0).opacity(0.22 * hear))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.9),
                                    cyanGlow.opacity(0.7 + 0.25 * hear),
                                    Color.white.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .overlay {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28 + 0.12 * hear),
                                    Color(red: 0.6, green: 0.9, blue: 1.0).opacity(0.08 + 0.2 * hear),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .shadow(color: cyanGlow.opacity((0.35 + 0.4 * hear) * pulseGlow), radius: 16 + 8 * hear, y: 2)

            VStack(spacing: 11) {
                HStack(spacing: 22) {
                    eye
                    eye
                }
                .offset(x: lookOffset)
                .scaleEffect(y: blinkScale, anchor: .center)

                Capsule()
                    .fill(LinearGradient(colors: [eyeTop, eyeBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: mood == .speaking ? 26 : 16, height: mood == .speaking ? 5 : 3.8)
                    .shadow(color: cyanGlow.opacity(0.55), radius: 4)
                    .offset(x: 8)
            }
            .offset(x: 16, y: 4)
        }
        .frame(width: headWidth, height: headHeight)
        .offset(y: (1 - appearProgress) * -(headHeight + 36))
        .opacity(Double(appearProgress))
        .allowsHitTesting(appearProgress > 0.45)
        .animation(.easeInOut(duration: 0.32), value: speechGlow)
    }

    private var eye: some View {
        Capsule()
            .fill(LinearGradient(colors: [eyeTop, eyeBottom], startPoint: .top, endPoint: .bottom))
            .frame(width: eyesOnly ? 13 : 15, height: eyesOnly ? 30 : 34)
            .overlay { Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.8) }
            .shadow(color: cyanGlow.opacity(0.65), radius: 5)
    }

    private func present(visible: Bool) {
        eyesDelayTask?.cancel()
        if visible {
            if eyesOnly {
                eyesProgress = 0
                eyesDelayTask = Task { @MainActor in
                    // Najpierw płynna poświata, potem sprężyste oczy
                    let ns = UInt64(max(eyesDelay, 0) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                        eyesProgress = 1
                    }
                    startIdleMotion()
                }
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { appearProgress = 1 }
                startIdleMotion()
            }
        } else {
            stopIdleMotion()
            if eyesOnly {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { eyesProgress = 0 }
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { appearProgress = 0 }
            }
        }
    }

    private func startIdleMotion() {
        stopIdleMotion()
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulseGlow = 1 }
        lookTask = Task { @MainActor in
            var dir: CGFloat = 1
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.35)) { lookOffset = 5.5 * dir }
                dir *= -1
                try? await Task.sleep(nanoseconds: 2_100_000_000)
            }
        }
        blinkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 2_500_000_000...4_800_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.07)) { blinkScale = 0.1 }
                try? await Task.sleep(nanoseconds: 85_000_000)
                withAnimation(.easeOut(duration: 0.1)) { blinkScale = 1 }
            }
        }
    }

    private func stopIdleMotion() {
        blinkTask?.cancel()
        lookTask?.cancel()
        blinkTask = nil
        lookTask = nil
        blinkScale = 1
        lookOffset = 0
        pulseGlow = 0.55
    }
}

enum DriveMateAvatarMood: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}
