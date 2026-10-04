import SwiftUI

/// Style przycisku z mechanicznym kliknięciem przy naciśnięciu.
struct MechanicalClickButtonStyle: ButtonStyle {
    var playOnPress: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, playOnPress {
                    MechanicalClickSound.play()
                }
            }
    }
}

extension View {
    func mechanicalClickStyle() -> some View {
        buttonStyle(MechanicalClickButtonStyle())
    }
}
