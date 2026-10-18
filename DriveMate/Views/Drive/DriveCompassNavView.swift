import SwiftUI
import CoreLocation

/// Tryb kompasu (rower): duża strzałka na środku + dystans prosto / do skrętu.
struct DriveCompassNavView: View {
    var guidance: NextTurnGuidance?
    var leadingChrome: CGFloat = 0
    var bottomChrome: CGFloat = 0
    var topChrome: CGFloat = 0

    @State private var appear = false

    private var direction: TurnDirection {
        guidance?.direction ?? .straight
    }

    private var distanceText: String {
        guard let guidance else { return "—" }
        if guidance.direction == .straight {
            return "\(metersLabel(guidance.distanceMeters)) prosto"
        }
        return "\(metersLabel(guidance.distanceMeters)) do skrętu \(guidance.direction.spoken)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.1),
                    Color(red: 0.08, green: 0.14, blue: 0.12),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: topChrome + 40)

                Image(systemName: arrowSymbol)
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(DriveMatePalette.limeRoute)
                    .shadow(color: DriveMatePalette.limeRoute.opacity(0.55), radius: 24, y: 4)
                    .rotationEffect(.degrees(arrowRotation))
                    .scaleEffect(appear ? 1 : 0.7)
                    .animation(.spring(response: 0.55, dampingFraction: 0.78), value: direction)
                    .animation(.spring(response: 0.48, dampingFraction: 0.8), value: appear)

                Text(distanceText)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: distanceText)

                Spacer(minLength: bottomChrome + 80)
            }
            .padding(.leading, leadingChrome * 0.2)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                appear = true
            }
        }
    }

    private var arrowSymbol: String {
        switch direction {
        case .straight: return "arrow.up"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        }
    }

    private var arrowRotation: Double {
        switch direction {
        case .straight: return 0
        case .left: return -8
        case .right: return 8
        }
    }

    private func metersLabel(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        let rounded = Int((meters / 5).rounded() * 5)
        return "\(max(rounded, 5)) m"
    }
}

struct CompassNavButton: View {
    var isActive: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "map.fill" : "location.north.line.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isActive
                            ? [
                                Color(red: 0.55, green: 1.0, blue: 0.55),
                                Color(red: 0.2, green: 0.75, blue: 0.35)
                            ]
                            : [
                                DriveMatePalette.limeRoute,
                                Color(red: 0.35, green: 0.85, blue: 0.55)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Color.black.opacity(isLight ? 0.14 : (isActive ? 0.35 : 0)))
                        .driveTileGlassCircle(interactive: true)
                }
                .overlay {
                    Circle().stroke(
                        isActive
                            ? Color(red: 0.4, green: 0.95, blue: 0.5).opacity(0.55)
                            : (isLight ? Color.black.opacity(0.25) : Color.white.opacity(0.3)),
                        lineWidth: 0.9
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Wróć do mapy" : "Tryb kompasu")
    }
}
