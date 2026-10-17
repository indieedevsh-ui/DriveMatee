import SwiftUI

enum SidebarPlacement: Equatable {
    case leading
    case bottom
}

/// Pasek zakładek: w poziomie po lewej, w pionie na dole.
/// Dynamic Island (landscape): czarny bleed pod wycięciem, etykiety wcięte wewnątrz.
struct SidebarView: View {
    @Binding var selected: AppTab
    var isDark: Bool
    var placement: SidebarPlacement = .leading
    /// Landscape: strefa pod Dynamic Island. Portrait: home indicator / bottom safe.
    var edgeSafe: CGFloat = 44

    private let labelSpan: CGFloat = 108
    private let bulgeWidth: CGFloat = 22
    private let edgeBleed: CGFloat = 40

    /// Szerokość zajmowana w landscape (dla ContentView / chrome).
    static func leadingWidth(edgeSafe: CGFloat) -> CGFloat {
        edgeSafe + 108 + 22
    }

    /// Wysokość zajmowana w portrait (dla ContentView / chrome).
    static func bottomHeight(edgeSafe: CGFloat) -> CGFloat {
        max(edgeSafe, 12) + 64 + 18
    }

    var body: some View {
        Group {
            switch placement {
            case .leading:
                leadingBar
            case .bottom:
                bottomBar
            }
        }
    }

    // MARK: - Landscape (lewa krawędź)

    private var leadingBar: some View {
        let contentWidth = edgeSafe + labelSpan + bulgeWidth
        let laidOutWidth = contentWidth + edgeBleed

        return GeometryReader { geo in
            let h = geo.size.height
            let gap: CGFloat = 8
            let vPad: CGFloat = max(36, 40)
            let itemH = max(72, (h - vPad * 2 - gap * 2) / 3)

            ZStack(alignment: .topLeading) {
                LeadingSidebarGlass(
                    selectedIndex: AppTab.allCases.firstIndex(of: selected) ?? 0,
                    itemHeight: itemH,
                    gap: gap,
                    topPad: vPad,
                    contentStartX: edgeBleed + edgeSafe,
                    bulgeWidth: bulgeWidth
                )
                .frame(width: laidOutWidth, height: h)

                VStack(spacing: gap) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab, vertical: true)
                            .frame(width: labelSpan, height: itemH)
                    }
                }
                .padding(.top, vPad)
                .padding(.leading, edgeBleed + edgeSafe)
            }
        }
        .frame(width: laidOutWidth)
        .offset(x: -edgeBleed)
        .padding(.trailing, -edgeBleed)
        .ignoresSafeArea(edges: [.top, .bottom, .leading])
    }

    // MARK: - Portrait (dolna krawędź)

    private var bottomBar: some View {
        let barBody: CGFloat = 64
        let bulge: CGFloat = 18
        let contentHeight = edgeSafe + barBody + bulge
        let laidOutHeight = contentHeight + edgeBleed

        return GeometryReader { geo in
            let w = geo.size.width
            let gap: CGFloat = 6
            let hPad: CGFloat = 10
            let itemW = max(72, (w - hPad * 2 - gap * 2) / 3)

            ZStack(alignment: .bottomLeading) {
                BottomSidebarGlass(
                    selectedIndex: AppTab.allCases.firstIndex(of: selected) ?? 0,
                    itemWidth: itemW,
                    gap: gap,
                    leadingPad: hPad,
                    contentStartY: bulge,
                    bulgeHeight: bulge
                )
                .frame(width: w, height: laidOutHeight)

                HStack(spacing: gap) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab, vertical: false)
                            .frame(width: itemW, height: barBody)
                    }
                }
                .padding(.leading, hPad)
                .padding(.bottom, edgeBleed + edgeSafe)
            }
        }
        .frame(height: laidOutHeight)
        .offset(y: edgeBleed)
        .padding(.top, -edgeBleed)
        .ignoresSafeArea(edges: [.leading, .trailing, .bottom])
    }

    private func tabButton(_ tab: AppTab, vertical: Bool) -> some View {
        let isActive = selected == tab
        return Button {
            MechanicalClickSound.play()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                selected = tab
            }
        } label: {
            Text(tab.title)
                .font(.system(
                    size: tab == .drive
                        ? (isActive ? (vertical ? 15 : 13) : 11)
                        : (isActive ? (vertical ? 22 : 16) : 13),
                    weight: isActive ? .bold : .semibold,
                    design: .default
                ))
                .tracking(isActive ? (tab == .drive ? 0.6 : 1.0) : 0.5)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.45))
                .shadow(color: isActive ? .white.opacity(0.85) : .clear, radius: isActive ? 10 : 0)
                .shadow(color: isActive ? .white.opacity(0.4) : .clear, radius: isActive ? 18 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Leading glass

private struct LeadingSidebarGlass: View {
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
            let shape = LeadingSidebarPath(
                bulgeCenterY: bulgeY,
                bulgeHeight: itemHeight + 16,
                bulgeWidth: bulgeWidth
            )

            ZStack {
                shape.fill(Color.black)
                shape.fill(.regularMaterial)
                    .opacity(0.5)
                    .mask(
                        HStack(spacing: 0) {
                            Color.clear.frame(width: max(0, contentStartX - 4))
                            Color.white
                        }
                    )
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

private struct LeadingSidebarPath: Shape {
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
        let half = bulgeHeight / 2
        let bulgeTop = bulgeCenterY - half
        let bulgeBottom = bulgeCenterY + half
        let pullIn: CGFloat = half * 0.38
        let pullOut: CGFloat = half * 0.42

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w - baseR, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: baseR), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: max(baseR, bulgeTop)))
        path.addCurve(
            to: CGPoint(x: w + bulgeWidth, y: bulgeCenterY),
            control1: CGPoint(x: w, y: bulgeTop + pullIn),
            control2: CGPoint(x: w + bulgeWidth, y: bulgeCenterY - pullOut)
        )
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

// MARK: - Bottom glass

private struct BottomSidebarGlass: View {
    let selectedIndex: Int
    let itemWidth: CGFloat
    let gap: CGFloat
    let leadingPad: CGFloat
    let contentStartY: CGFloat
    let bulgeHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let bulgeX = leadingPad + CGFloat(selectedIndex) * (itemWidth + gap) + itemWidth / 2
            let shape = BottomSidebarPath(
                bulgeCenterX: bulgeX,
                bulgeWidth: itemWidth + 20,
                bulgeHeight: bulgeHeight
            )

            ZStack {
                shape.fill(Color.black)
                shape.fill(.regularMaterial)
                    .opacity(0.5)
                    .mask(
                        VStack(spacing: 0) {
                            Color.white
                            Color.clear.frame(height: max(0, size.height - contentStartY - 4))
                        }
                    )
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.04), location: 0.0),
                            .init(color: Color.black.opacity(0.18), location: 0.16),
                            .init(color: Color.black.opacity(0.55), location: 0.42),
                            .init(color: .black, location: 0.78),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}

/// Pasek na dole z falą w górę przy aktywnej zakładce.
private struct BottomSidebarPath: Shape {
    var bulgeCenterX: CGFloat
    var bulgeWidth: CGFloat
    var bulgeHeight: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bulgeCenterX, bulgeWidth) }
        set {
            bulgeCenterX = newValue.first
            bulgeWidth = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let h = rect.height
        let w = rect.width
        let baseR: CGFloat = 22
        // Góra treści paska (pod falą)
        let topY = bulgeHeight
        let half = bulgeWidth / 2
        let left = bulgeCenterX - half
        let right = bulgeCenterX + half
        let pullIn = half * 0.38
        let pullOut = half * 0.42

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: topY + baseR))
        path.addQuadCurve(
            to: CGPoint(x: baseR, y: topY),
            control: CGPoint(x: 0, y: topY)
        )
        path.addLine(to: CGPoint(x: max(baseR, left), y: topY))

        // Fala w górę
        path.addCurve(
            to: CGPoint(x: bulgeCenterX, y: 0),
            control1: CGPoint(x: left + pullIn, y: topY),
            control2: CGPoint(x: bulgeCenterX - pullOut, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: right, y: topY),
            control1: CGPoint(x: bulgeCenterX + pullOut, y: 0),
            control2: CGPoint(x: right - pullIn, y: topY)
        )

        path.addLine(to: CGPoint(x: w - baseR, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: w, y: topY + baseR),
            control: CGPoint(x: w, y: topY)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }
}

/// Prawy pasek — pełna wysokość, flush do prawej krawędzi (tylko landscape + nawigacja).
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
