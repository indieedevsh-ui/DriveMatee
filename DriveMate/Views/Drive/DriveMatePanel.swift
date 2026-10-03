import SwiftUI

/// Kompaktowy panel komend — awatar jest osobno na górze.
/// Podczas nawigacji: kafelek skrętu + tymczasowy przycisk Drive (pastylka tekstowa).
struct DriveMatePanel: View {
    @ObservedObject var assistant: DriveMateAssistant
    var guidance: NextTurnGuidance?
    /// Tymczasowy przycisk „Drive” + pastylka do wpisania prośby podczas nawigacji.
    var showNavDriveComposer: Bool = false

    @State private var typed = ""
    @State private var showComposer = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if assistant.isAvatarVisible, !assistant.reply.isEmpty, !assistant.isWakeListening {
                Text(assistant.reply)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 260, alignment: .leading)
                    .liquidGlassRect(cornerRadius: 16, .clear)
            }

            if let guidance {
                TurnGuidanceTile(guidance: guidance)
            }

            if showNavDriveComposer {
                navDriveControls
            } else if guidance == nil {
                controlsRow
                if showComposer {
                    composerPill
                }
            }
        }
        .alert("Drive Mate", isPresented: Binding(
            get: { assistant.lastError != nil },
            set: { if !$0 { assistant.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { assistant.lastError = nil }
        } message: {
            Text(assistant.lastError ?? "")
        }
    }

    private var navDriveControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if showComposer {
                composerPill
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                    showComposer.toggle()
                }
            } label: {
                Text("Drive")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background {
                        Capsule(style: .continuous)
                            .fill(DriveMatePalette.limeRoute)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Drive — wpisz prośbę")
        }
    }

    private var composerPill: some View {
        HStack(spacing: 8) {
            TextField("Hey Drive…", text: $typed)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .liquidGlassCapsule(.clear)
                .onSubmit { sendTyped() }

            Button {
                sendTyped()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(DriveMatePalette.limeRoute, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 280)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button {
                showComposer.toggle()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .liquidGlassCircle(.clear.interactive())
            }
            .buttonStyle(.plain)

            Button {
                assistant.toggleListening()
            } label: {
                Image(systemName: assistant.state == .listening && !assistant.isWakeListening ? "mic.fill" : "mic")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(assistant.state == .listening && !assistant.isWakeListening ? .black : .white)
                    .frame(width: 40, height: 40)
                    .background {
                        if assistant.state == .listening && !assistant.isWakeListening {
                            Circle().fill(DriveMatePalette.limeRoute)
                        } else {
                            Circle().fill(Color.clear)
                                .liquidGlassCircle(.clear.interactive())
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func sendTyped() {
        let value = typed
        typed = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            showComposer = false
        }
        assistant.submitText(value)
    }
}
