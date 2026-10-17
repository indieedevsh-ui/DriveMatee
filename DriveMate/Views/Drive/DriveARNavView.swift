import SwiftUI
import AVFoundation

/// Podgląd tylnej kamery podczas nawigacji + nakładki skrętu (100 m / skrzyżowanie).
struct DriveARNavView: View {
    @ObservedObject var camera: CameraRecorderService
    var guidance: NextTurnGuidance?
    /// Symbol przypomnienia na skrzyżowaniu (znika po 5 s).
    var intersectionReminder: TurnDirection?
    var leadingChrome: CGFloat = 168

    var body: some View {
        ZStack {
            if camera.permissionGranted {
                CameraPreviewView(session: camera.session, camera: camera)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(camera.lastError ?? "Włącz dostęp do kamery w Ustawieniach.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.leading, leadingChrome * 0.2)
            }

            // Przyciemnienie krawędzi — czytelniejszy symbol na środku.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.4)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ARTurnSymbolOverlay(
                guidance: guidance,
                intersectionReminder: intersectionReminder
            )
            .padding(.leading, leadingChrome * 0.15)
        }
    }
}

/// Środkowy symbol skrętu: zbliżenie ≤ 100 m oraz przypomnienie na skrzyżowaniu.
struct ARTurnSymbolOverlay: View {
    var guidance: NextTurnGuidance?
    var intersectionReminder: TurnDirection?

    private var approachVisible: Bool {
        guard intersectionReminder == nil, let guidance else { return false }
        return guidance.distanceMeters <= NextTurnGuidance.arApproachWithinMeters
            && guidance.direction != .straight
    }

    var body: some View {
        ZStack {
            if let reminder = intersectionReminder, reminder != .straight {
                turnBadge(
                    direction: reminder,
                    caption: "Skręć \(reminder.spoken)",
                    prominent: true
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            } else if approachVisible, let guidance {
                turnBadge(
                    direction: guidance.direction,
                    caption: guidance.distanceLabel,
                    prominent: guidance.isImminent
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.88).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: approachVisible)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: intersectionReminder)
        .animation(.easeInOut(duration: 0.25), value: guidance?.distanceLabel)
    }

    private func turnBadge(direction: TurnDirection, caption: String, prominent: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: direction.symbolName)
                .font(.system(size: prominent ? 72 : 58, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
                .symbolEffect(.pulse, options: .repeating, isActive: prominent)

            Text(caption)
                .font(.system(size: prominent ? 22 : 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .liquidGlassRect(cornerRadius: 28, .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.35, green: 0.85, blue: 1).opacity(0.35), radius: 18, y: 4)
    }
}

struct ARNavButton: View {
    var isActive: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "map.fill" : "camera.viewfinder")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isActive
                            ? [
                                Color(red: 0.55, green: 1.0, blue: 0.55),
                                Color(red: 0.2, green: 0.75, blue: 0.35)
                            ]
                            : (isLight
                                ? [Color.black.opacity(0.9), Color(white: 0.25)]
                                : [
                                    Color(red: 1.0, green: 0.92, blue: 0.55),
                                    Color(red: 1.0, green: 0.65, blue: 0.2)
                                ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Color.black.opacity(isLight ? 0.14 : (isActive ? 0.35 : 0)))
                        .liquidGlassCircle(.clear.interactive())
                }
                .overlay {
                    Circle().stroke(
                        isActive
                            ? Color(red: 0.4, green: 0.95, blue: 0.5).opacity(0.55)
                            : (isLight ? Color.black.opacity(0.25) : Color.white.opacity(0.3)),
                        lineWidth: 0.9
                    )
                }
                .shadow(
                    color: isActive
                        ? Color(red: 0.3, green: 0.9, blue: 0.4).opacity(0.4)
                        : (isLight ? Color.black.opacity(0.15) : Color.orange.opacity(0.3)),
                    radius: 8
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Wróć do mapy" : "Tryb AR — kamera")
    }
}
