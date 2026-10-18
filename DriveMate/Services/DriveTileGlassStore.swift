import Foundation
import SwiftUI
import Combine

/// Przezroczystość liquid glass kafelków Drive (głos: zwiększ / zmniejsz).
/// Oba tryby używają `.regular` (mocna deformacja tła / gęsty blur), różni się tylko krycie:
/// - `denser == false` → regular @ 35% (bardziej przezroczyste)
/// - `denser == true`  → regular @ 90% (mniej przezroczyste)
@MainActor
final class DriveTileGlassStore: ObservableObject {
    static let shared = DriveTileGlassStore()

    /// `true` = mniej przezroczyste (regular 90%).
    @Published private(set) var denser: Bool = false

    private let key = "driveMate.tiles.glass.denser.v1"

    private init() {
        denser = UserDefaults.standard.bool(forKey: key)
    }

    /// `moreTransparent: true` → 35% regular; `false` → 90% regular.
    @discardableResult
    func setMoreTransparent(_ moreTransparent: Bool) -> String {
        let wantDenser = !moreTransparent
        if denser == wantDenser {
            return moreTransparent
                ? "Kafelki są już bardziej przezroczyste."
                : "Kafelki mają już mocniejsze szkło."
        }
        denser = wantDenser
        UserDefaults.standard.set(wantDenser, forKey: key)
        objectWillChange.send()
        return moreTransparent
            ? "Zwiększam przezroczystość kafelków."
            : "Zmniejszam przezroczystość kafelków."
    }

    /// Zawsze regular — żeby tło było wyraźnie deformowane / gęstsze.
    var glassStyle: DriveGlassStyle { .regular }

    /// Krycie warstwy glass: 35% (przezroczystsze) / 90% (gęstsze).
    var glassLayerOpacity: Double { denser ? 0.90 : 0.35 }
}
