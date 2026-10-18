import SwiftUI

/// Kafelek liquid glass ze strzałką skrętu i odległością / „tutaj”.
struct TurnGuidanceTile: View {
    let guidance: NextTurnGuidance
    /// Tryb rowerowy — znacznie większy kafelek skrętu.
    var enlarged: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var bounce: CGFloat = 0

    private var isLight: Bool { colorScheme == .light }
    private var foreground: Color { isLight ? .black : .white }

    var body: some View {
        VStack(spacing: enlarged ? 12 : 8) {
            Image(systemName: guidance.direction.symbolName)
                .font(.system(size: enlarged ? 52 : 30, weight: .bold))
                .foregroundStyle(foreground)
                .shadow(color: .black.opacity(isLight ? 0.12 : 0.35), radius: 2, y: 1)
                .offset(y: bounce)
                .frame(height: enlarged ? 64 : 36)

            Text(guidance.distanceLabel)
                .font(.system(size: enlarged ? (guidance.isImminent ? 24 : 20) : (guidance.isImminent ? 16 : 14), weight: .heavy, design: .rounded))
                .foregroundStyle(foreground)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(.horizontal, enlarged ? 22 : 14)
        .padding(.vertical, enlarged ? 18 : 12)
        .frame(minWidth: enlarged ? 132 : 84)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(isLight ? 0.14 : 0))
                .driveTileGlassRect(cornerRadius: 18, interactive: true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.32),
                    lineWidth: 0.9
                )
        }
        .shadow(
            color: isLight
                ? Color.black.opacity(guidance.isImminent ? 0.2 : 0.1)
                : Color(red: 0.4, green: 0.85, blue: 1).opacity(guidance.isImminent ? 0.4 : 0.16),
            radius: 8,
            y: 2
        )
        .onChange(of: guidance.isImminent) { _, imminent in
            updateBounce(imminent)
        }
        .onAppear { updateBounce(guidance.isImminent) }
        .accessibilityLabel("\(guidance.direction.spoken), \(guidance.distanceLabel)")
    }

    private func updateBounce(_ imminent: Bool) {
        if imminent {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                bounce = -7
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                bounce = 0
            }
        }
    }
}
