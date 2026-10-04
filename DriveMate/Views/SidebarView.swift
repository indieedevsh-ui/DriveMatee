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
    /// Wyjście w lewo poza ekran — krawędź AA / material nie jest widoczna.
    private let edgeBleed: CGFloat = 40

    private var contentWidth: CGFloat { leadingSafe + labelWidth + bulgeWidth }
    private var laidOutWidth: CGFloat { contentWidth + edgeBleed }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            // Większy vPad → pełna wysokość fali także dla DRIVE / SETTINGS (nie skraca przy krawędziach).
            let gap: CGFloat = 8
            let edgeReserve: CGFloat = 40
            let vPad: CGFloat = max(36, edgeReserve)
            let itemH = max(72, (h - vPad * 2 - gap * 2) / 3)

            ZStack(alignment: .topLeading) {
                SidebarGlassShape(
                    selectedIndex: AppTab.allCases.firstIndex(of: selected) ?? 0,
                    itemHeight: itemH,
                    gap: gap,
                    topPad: vPad,
                    contentStartX: edgeBleed + leadingSafe,
                    bulgeWidth: bulgeWidth
                )
                .frame(width: laidOutWidth, height: h)

                VStack(spacing: gap) {
                    ForEach(AppTab.allCases) { tab in
                        let isActive = selected == tab
                        Button {
                            MechanicalClickSound.play()
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                selected = tab
                            }
                        } label: {
                            Text(tab.title)
                                .font(.system(
                                    size: tab == .drive
                                        ? (isActive ? 15 : 11)
                                        : (isActive ? 22 : 13),
                                    weight: isActive ? .bold : .semibold,
                                    design: .default
                                ))
                                .tracking(isActive ? (tab == .drive ? 0.6 : 1.2) : 0.6)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.75)
                                .lineLimit(2)
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
                .padding(.leading, edgeBleed + leadingSafe)
            }
        }
        .frame(width: laidOutWidth)
        .offset(x: -edgeBleed)
        .padding(.trailing, -edgeBleed)
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
                shape.fill(Color.black)

                // Material tylko od strefy treści — nie na bledzie poza ekranem.
                shape.fill(.regularMaterial)
                    .opacity(0.5)
                    .mask(
                        HStack(spacing: 0) {
                            Color.clear.frame(width: max(0, contentStartX - 4))
                            Color.white
                        }
                    )

                // 100% czarny pod island → liquid glass przy wewnętrznej krawędzi
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: max(0.18, contentStartX / max(size.width, 1) * 0.9)),
                            .init(color: Color.black.opacity(0.55), location: 0.58),
                            .init(color: Color.black.opacity(0.18), location: 0.84),
                            .init(color: Color.black.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
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

        // Stała wysokość fali dla DRIVE / RECORDER / SETTINGS — bez skracania przy krawędziach.
        let half = bulgeHeight / 2
        let bulgeTop = bulgeCenterY - half
        let bulgeBottom = bulgeCenterY + half

        // Kontrolki krzywej — lustrzane względem środka (ładna „soczewka”)
        let pullIn: CGFloat = half * 0.38
        let pullOut: CGFloat = half * 0.42

        var path = Path()
        // Lewa krawędź = x:0 w szerszym frame z bleem → po offsetcie poza ekranem.
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w - baseR, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: baseR), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: max(baseR, bulgeTop)))

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
