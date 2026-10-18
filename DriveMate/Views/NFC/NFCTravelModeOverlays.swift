import SwiftUI

/// Wybór: zakodować pusty tag na tryb samochodowy / rowerowy.
struct NFCEncodeTagSheet: View {
    var onSelect: (TravelMode) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(DriveMatePalette.limeRoute)

            Text("Tag NFC")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Wybierz tryb, a potem raz przybliż tag do telefonu. Potem wystarczy samo przybliżenie.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            VStack(spacing: 12) {
                ForEach(TravelMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 28)
                            Text(mode.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.black.opacity(0.88))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background {
                            Capsule(style: .continuous)
                                .fill(DriveMatePalette.limeRoute)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Anuluj", action: onCancel)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
        .travelModeGlass(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
        .padding(.horizontal, 28)
    }
}

/// Płynne okienko trybu po odczycie zakodowanego tagu — znika po chwili.
struct NFCTravelModeToast: View {
    let mode: TravelMode

    @State private var appear = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DriveMatePalette.limeRoute)
                .scaleEffect(appear ? 1 : 0.7)

            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Tag NFC rozpoznany")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .travelModeGlass(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .scaleEffect(appear ? 1 : 0.86)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                appear = true
            }
        }
    }
}

private extension View {
    /// Clear liquid glass + 70% regular (okienka trybu samochód / rower).
    /// Na iOS 18–25: warstwowy blur (ultraThin + thick).
    func travelModeGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            ZStack {
                shape
                    .fill(Color.clear)
                    .liquidGlass(.clear, in: shape)
                shape
                    .fill(Color.clear)
                    .liquidGlass(.regular, in: shape)
                    .opacity(0.7)
            }
        }
    }
}
