import SwiftUI
import UIKit

/// Styl „szkła” używany w API `liquidGlass*` — na iOS 26+ mapuje na prawdziwy Glass.
enum DriveGlassStyle: Equatable {
    case clear
    case regular

    var isClear: Bool {
        if case .clear = self { return true }
        return false
    }

    /// Kompatybilność ze starym `Glass.clear.interactive()`.
    func interactive() -> DriveGlassSpec {
        DriveGlassSpec(style: self, interactive: true)
    }
}

struct DriveGlassSpec: Equatable {
    var style: DriveGlassStyle
    var interactive: Bool
}

/// Czy device ma natywny liquid glass (iOS 26+).
enum DriveGlassAvailability {
    static var usesNativeLiquidGlass: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

/// Prawdziwy liquid glass (UIGlassEffect) na iOS 26+; niżej — gęsty UIBlurEffect.
struct LiquidGlassBackground: UIViewRepresentable {
    var style: DriveGlassStyle = .clear
    var cornerRadius: CGFloat = 28
    var tint: UIColor? = nil
    var interactive: Bool = false

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: makeEffect())
        view.layer.cornerRadius = cornerRadius
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = makeEffect()
        uiView.layer.cornerRadius = cornerRadius
        uiView.clipsToBounds = true
    }

    private func makeEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: style == .clear ? .clear : .regular)
            effect.isInteractive = interactive
            if let tint { effect.tintColor = tint }
            return effect
        }
        // iOS 18–25: gęstszy blur zamiast liquid glass.
        let blur: UIBlurEffect.Style = style == .clear ? .systemUltraThinMaterialDark : .systemThickMaterialDark
        return UIBlurEffect(style: blur)
    }
}

struct ConceptGlass: View {
    var cornerRadius: CGFloat = 30
    /// Lekki połysk na wierzchu (0 = tylko glass).
    var opacity: Double = 0.08
    var compact: Bool = false
    var clear: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .background {
                LiquidGlassBackground(
                    style: clear ? .clear : .regular,
                    cornerRadius: cornerRadius
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(opacity * 0.25))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
            .shadow(color: .black.opacity(compact ? 0.15 : 0.28), radius: compact ? 8 : 14, y: compact ? 3 : 6)
    }
}

extension View {
    func conceptGlass(cornerRadius: CGFloat = 30, opacity: Double = 0.08, clear: Bool = true) -> some View {
        background {
            ConceptGlass(cornerRadius: cornerRadius, opacity: opacity, clear: clear)
        }
    }

    /// Liquid glass na iOS 26+; na iOS 18–25 — Material / blur w kształcie.
    func liquidGlass<S: Shape>(
        _ glass: DriveGlassStyle = .clear,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassShapeModifier(glass: glass, shape: shape, interactive: interactive))
    }

    func liquidGlassCapsule(_ glass: DriveGlassStyle = .clear, interactive: Bool = false) -> some View {
        liquidGlass(glass, in: Capsule(style: .continuous), interactive: interactive)
    }

    func liquidGlassCapsule(_ spec: DriveGlassSpec) -> some View {
        liquidGlassCapsule(spec.style, interactive: spec.interactive)
    }

    func liquidGlassCircle(_ glass: DriveGlassStyle = .clear, interactive: Bool = false) -> some View {
        liquidGlass(glass, in: Circle(), interactive: interactive)
    }

    func liquidGlassCircle(_ spec: DriveGlassSpec) -> some View {
        liquidGlassCircle(spec.style, interactive: spec.interactive)
    }

    func liquidGlassRect(cornerRadius: CGFloat, _ glass: DriveGlassStyle = .clear, interactive: Bool = false) -> some View {
        liquidGlass(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive)
    }

    func liquidGlassRect(cornerRadius: CGFloat, _ spec: DriveGlassSpec) -> some View {
        liquidGlassRect(cornerRadius: cornerRadius, spec.style, interactive: spec.interactive)
    }

    /// Liquid glass kafelków Drive — zawsze regular (deformacja tła), 35% / 90% krycia.
    func driveTileGlassRect(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(DriveTileGlassModifier(kind: .rect(cornerRadius), interactive: interactive))
    }

    func driveTileGlassCapsule(interactive: Bool = false) -> some View {
        modifier(DriveTileGlassModifier(kind: .capsule, interactive: interactive))
    }

    func driveTileGlassCircle(interactive: Bool = false) -> some View {
        modifier(DriveTileGlassModifier(kind: .circle, interactive: interactive))
    }
}

private struct LiquidGlassShapeModifier<S: Shape>: ViewModifier {
    var glass: DriveGlassStyle
    var shape: S
    var interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let native: Glass = glass == .clear ? .clear : .regular
            content.glassEffect(interactive ? native.interactive() : native, in: shape)
        } else {
            // iOS 18–25: gęstszy / bardziej przezroczysty blur (bez liquid glass).
            content.background {
                shape
                    .fill(.clear)
                    .background {
                        LegacyBlurFill(style: glass)
                    }
                    .clipShape(shape)
            }
            .overlay {
                shape.stroke(Color.white.opacity(glass == .clear ? 0.28 : 0.18), lineWidth: 0.8)
            }
        }
    }
}

/// Blur fallback pod kształty SwiftUI (iOS 18–25).
private struct LegacyBlurFill: UIViewRepresentable {
    var style: DriveGlassStyle

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: blurEffect)
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = blurEffect
    }

    private var blurEffect: UIBlurEffect {
        // clear → bardziej przezroczysty; regular → gęstszy material.
        UIBlurEffect(style: style == .clear ? .systemUltraThinMaterialDark : .systemThickMaterialDark)
    }
}

private enum DriveTileGlassKind {
    case rect(CGFloat)
    case capsule
    case circle
}

private struct DriveTileGlassModifier: ViewModifier {
    @ObservedObject private var store = DriveTileGlassStore.shared
    var kind: DriveTileGlassKind
    var interactive: Bool

    func body(content: Content) -> some View {
        let glass = store.glassStyle
        Group {
            switch kind {
            case .rect(let radius):
                content.liquidGlassRect(cornerRadius: radius, glass, interactive: interactive)
            case .capsule:
                content.liquidGlassCapsule(glass, interactive: interactive)
            case .circle:
                content.liquidGlassCircle(glass, interactive: interactive)
            }
        }
        .opacity(store.glassLayerOpacity)
        .animation(.easeInOut(duration: 0.35), value: store.denser)
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Ciemny"
        case .light: "Jasny"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}

enum DriveMatePalette {
    static let neonGreen = Color(red: 0.35, green: 0.98, blue: 0.42)
    static let neonGreenMid = Color(red: 0.18, green: 0.88, blue: 0.38)
    static let neonGreenDeep = Color(red: 0.08, green: 0.62, blue: 0.28)
    /// Limonkowa linia nawigacji
    static let limeRoute = Color(red: 0.72, green: 1.0, blue: 0.22)
    static let limeRouteUI = UIColor(red: 0.72, green: 1.0, blue: 0.22, alpha: 1)
    static let glassStroke = Color.white.opacity(0.42)
    static let speedText = Color.black
    static let cardFillDark = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let cardFillLight = Color.white
}
