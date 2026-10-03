import SwiftUI

/// Sidebar full-height przy lewej krawędzi.
/// Dynamic Island: czarny obszar wchodzi pod wycięcie, tekst jest wcięty WEWNĄTRZ paska
/// (bez dziury / „wywalenia” sidebara w prawo).
struct SidebarView: View {
    @Binding var selected: AppTab
    var isDark: Bool
    /// Szerokość strefy pod Dynamic Island / safe area — wewnątrz sidebara.
    var leadingSafe: CGFloat = 44

    private let labelWidth: CGFloat = 108
    private let bulgeWidth: CGFloat = 22

    private var totalWidth: CGFloat { leadingSafe + labelWidth + bulgeWidth }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            // Równomiernie na CAŁĄ wysokość — dłuższe marginesy = wyższy pasek.
            let vPad: CGFloat = 20
            let gap: CGFloat = 8
            let itemH = max(72, (h - vPad * 2 - gap * 2) / 3)

            ZStack(alignment: .topLeading) {
                SidebarGlassShape(
                    selectedIndex: AppTab.allCases.firstIndex(of: selected) ?? 0,
                    itemHeight: itemH,
                    gap: gap,
                    topPad: vPad,
                    contentStartX: leadingSafe,
                    bulgeWidth: bulgeWidth
                )
                .frame(width: totalWidth, height: h)

                VStack(spacing: gap) {
                    ForEach(AppTab.allCases) { tab in
                        let isActive = selected == tab
                        Button {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                selected = tab
                            }
                        } label: {
                            Text(tab.title)
                                .font(.system(
                                    size: isActive ? 22 : 13,
                                    weight: isActive ? .bold : .semibold,
                                    design: .default
                                ))
                                .tracking(isActive ? 1.2 : 0.6)
                                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.45))
                                .shadow(color: isActive ? .white.opacity(0.85) : .clear, radius: isActive ? 10 : 0)
                                .shadow(color: isActive ? .white.opacity(0.4) : .clear, radius: isActive ? 18 : 0)
                                .frame(width: labelWidth, height: itemH)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, vPad)
                .padding(.leading, leadingSafe)
            }
        }
        .frame(width: totalWidth)
        .ignoresSafeArea(edges: [.top, .bottom, .leading])
    }
}

private struct SidebarGlassShape: View {
    let selectedIndex: Int
    let itemHeight: CGFloat
    let gap: CGFloat
    let topPad: CGFloat
    let contentStartX: CGFloat
    let bulgeWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let bulgeY = topPad + CGFloat(selectedIndex) * (itemHeight + gap) + itemHeight / 2
            let shape = SidebarPath(
                bulgeCenterY: bulgeY,
                bulgeHeight: itemHeight + 16,
                bulgeWidth: bulgeWidth
            )

            ZStack {
                shape.fill(.regularMaterial)

                // 100% czarny pod island → liquid glass przy wewnętrznej krawędzi
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: max(0.15, contentStartX / max(size.width, 1) * 0.85)),
                            .init(color: Color.black.opacity(0.65), location: 0.55),
                            .init(color: Color.black.opacity(0.22), location: 0.82),
                            .init(color: Color.black.opacity(0.06), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.white.opacity(0.32)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct SidebarPath: Shape {
    var bulgeCenterY: CGFloat
    var bulgeHeight: CGFloat
    var bulgeWidth: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bulgeCenterY, bulgeHeight) }
        set {
            bulgeCenterY = newValue.first
            bulgeHeight = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width - bulgeWidth
        let h = rect.height
        let baseR: CGFloat = 28
        let edgePad = baseR + 6

        // Symetryczna wypukłość wokół środka — ta sama fala dla Drive / Record / Settings.
        var half = bulgeHeight / 2
        if bulgeCenterY - half < edgePad {
            half = max(28, bulgeCenterY - edgePad)
        }
        if bulgeCenterY + half > h - edgePad {
            half = max(28, h - edgePad - bulgeCenterY)
        }
        // Użyj mniejszej półwysokości, żeby obie strony były równe
        let topLimit = bulgeCenterY - edgePad
        let bottomLimit = h - edgePad - bulgeCenterY
        half = min(half, topLimit, bottomLimit, bulgeHeight / 2)
        half = max(half, 28)

        let bulgeTop = bulgeCenterY - half
        let bulgeBottom = bulgeCenterY + half

        // Kontrolki krzywej — lustrzane względem środka (ładna „soczewka”)
        let pullIn: CGFloat = half * 0.38
        let pullOut: CGFloat = half * 0.42

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w - baseR, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: baseR), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: bulgeTop))

        // Górna połowa fali → czubek
        path.addCurve(
            to: CGPoint(x: w + bulgeWidth, y: bulgeCenterY),
            control1: CGPoint(x: w, y: bulgeTop + pullIn),
            control2: CGPoint(x: w + bulgeWidth, y: bulgeCenterY - pullOut)
        )
        // Dolna połowa fali → powrót (lustrzane control points)
        path.addCurve(
            to: CGPoint(x: w, y: bulgeBottom),
            control1: CGPoint(x: w + bulgeWidth, y: bulgeCenterY + pullOut),
            control2: CGPoint(x: w, y: bulgeBottom - pullIn)
        )

        path.addLine(to: CGPoint(x: w, y: h - baseR))
        path.addQuadCurve(to: CGPoint(x: w - baseR, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// Prawy pasek — pełna wysokość, flush do prawej krawędzi.
struct RightGlassEdge: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.08), location: 0.0),
                    .init(color: Color.black.opacity(0.45), location: 0.4),
                    .init(color: Color.black.opacity(0.85), location: 0.75),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, 24)
        }
        .frame(width: 22)
        .ignoresSafeArea(edges: [.top, .bottom, .trailing])
        .allowsHitTesting(false)
    }
}
