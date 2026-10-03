import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("appearance") var appearanceRaw: String = AppAppearance.dark.rawValue {
        didSet { objectWillChange.send() }
    }

    @AppStorage("recorderEnabled") var recorderEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("autoMuteEnabled") var autoMuteEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("musicVolume") var musicVolume: Double = 0.75 {
        didSet {
            objectWillChange.send()
            volumeDidChange?(musicVolume)
        }
    }

    var volumeDidChange: ((Double) -> Void)?

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .dark }
        set { appearanceRaw = newValue.rawValue }
    }

    var isDark: Bool { appearance == .dark }
}
