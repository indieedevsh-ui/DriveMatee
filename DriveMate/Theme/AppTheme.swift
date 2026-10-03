import SwiftUI
import UIKit

/// Prawdziwy liquid glass (UIGlassEffect) — clear / regular.
struct LiquidGlassBackground: UIViewRepresentable {
    var style: UIGlassEffect.Style = .clear
    var cornerRadius: CGFloat = 28
    var tint: UIColor? = nil
    var interactive: Bool = false

    func makeUIView(context: Context) -> UIVisualEffectView {
        let effect = UIGlassEffect(style: style)
        effect.isInteractive = interactive
        if let tint { effect.tintColor = tint }
        let view = UIVisualEffectView(effect: effect)
        view.layer.cornerRadius = cornerRadius
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        let effect = UIGlassEffect(style: style)
        effect.isInteractive = interactive
        if let tint { effect.tintColor = tint }
        uiView.effect = effect
        uiView.layer.cornerRadius = cornerRadius
        uiView.clipsToBounds = true
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

    /// SwiftUI liquid glass — preferowany dla kształtów natywnych.
    func liquidGlass<S: Shape>(
        _ glass: Glass = .clear,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        glassEffect(interactive ? glass.interactive() : glass, in: shape)
    }

    func liquidGlassCapsule(_ glass: Glass = .clear, interactive: Bool = false) -> some View {
        liquidGlass(glass, in: Capsule(style: .continuous), interactive: interactive)
    }

    func liquidGlassCircle(_ glass: Glass = .clear, interactive: Bool = false) -> some View {
        liquidGlass(glass, in: Circle(), interactive: interactive)
    }

    func liquidGlassRect(cornerRadius: CGFloat, _ glass: Glass = .clear, interactive: Bool = false) -> some View {
        liquidGlass(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive)
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
