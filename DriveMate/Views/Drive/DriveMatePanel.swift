import SwiftUI

/// Prawy górny róg podczas nawigacji: oczy Drive Mate albo kafelek skrętu (≤ 350 m).
struct DriveMatePanel: View {
    @ObservedObject var assistant: DriveMateAssistant
    var guidance: NextTurnGuidance?

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let guidance, guidance.showsTurnTile {
                TurnGuidanceTile(guidance: guidance)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                eyesActivateButton
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: guidance?.maneuverID)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: guidance?.showsTurnTile)
        .alert("Drive Mate", isPresented: Binding(
            get: { assistant.lastError != nil },
            set: { if !$0 { assistant.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { assistant.lastError = nil }
        } message: {
            Text(assistant.lastError ?? "")
        }
    }

    /// Jeden większy przycisk z oczami — zawsze uruchamia nasłuch głosowy.
    private var eyesActivateButton: some View {
        let isListening = assistant.state == .listening && !assistant.isWakeListening
        return Button {
            assistant.summon()
        } label: {
            DriveMateEyesButtonLabel(isListening: isListening, speechGlow: assistant.speechGlow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aktywuj Drive Mate głosowo")
    }
}

/// Oczy Drive Mate w przycisku (kompaktowa wersja awatara).
struct DriveMateEyesButtonLabel: View {
    var isListening: Bool
    var speechGlow: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private let eyeTop = Color(red: 0.35, green: 0.72, blue: 0.98)
    private let eyeBottom = Color(red: 0.15, green: 0.48, blue: 0.88)
    private let cyanGlow = Color(red: 0.55, green: 0.94, blue: 1.0)

    var body: some View {
        HStack(spacing: 10) {
            eye
            eye
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 56, minHeight: 52)
        .background {
            if isListening {
                Capsule(style: .continuous)
                    .fill(DriveMatePalette.limeRoute.opacity(0.92))
            } else {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(isLight ? 0.14 : 0))
                    .liquidGlassCapsule(.clear.interactive())
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    isListening
                        ? Color.black.opacity(0.12)
                        : (isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.22)),
                    lineWidth: 1
                )
        }
        .shadow(
            color: cyanGlow.opacity(0.25 + 0.45 * speechGlow),
            radius: 8 + 4 * speechGlow
        )
        .scaleEffect(isListening ? 1.04 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isListening)
    }

    private var eye: some View {
        Capsule()
            .fill(LinearGradient(colors: [eyeTop, eyeBottom], startPoint: .top, endPoint: .bottom))
            .frame(width: 11, height: 26)
            .overlay { Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.7) }
            .shadow(color: cyanGlow.opacity(0.55), radius: 3)
    }
}
