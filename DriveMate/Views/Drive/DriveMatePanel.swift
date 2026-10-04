import SwiftUI

/// Kompaktowy panel komend — awatar jest osobno na górze.
/// Podczas nawigacji: kafelek skrętu. Poza nawigacją: klawiatura / mikrofon.
struct DriveMatePanel: View {
    @ObservedObject var assistant: DriveMateAssistant
    var guidance: NextTurnGuidance?

    @State private var typed = ""
    @State private var showComposer = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let guidance {
                TurnGuidanceTile(guidance: guidance)
            } else {
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
