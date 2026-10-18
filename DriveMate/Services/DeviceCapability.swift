import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Możliwości sprzętu pod kątem Apple Intelligence / Foundation Models.
enum DeviceCapability {

    /// iPhone 15 Pro / 15 Pro Max oraz nowsze (A17 Pro+ / A18+), które mogą używać Foundation Models.
    /// Zwykły iPhone 15 / 15 Plus — nie.
    static var supportsFoundationModelsHardware: Bool {
        #if targetEnvironment(simulator)
        // Na symulatorze pozwalamy przełączać tryby (test UI).
        return true
        #else
        return isIPhone15ProOrNewer
        #endif
    }

    /// Identyfikator maszyny, np. `iPhone16,1`.
    static var machineIdentifier: String {
        #if canImport(UIKit)
        if let simulator = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulator.isEmpty {
            return simulator
        }
        #endif
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    /// Opis dla ustawień.
    static var hardwareSummary: String {
        if supportsFoundationModelsHardware {
            return "To urządzenie może korzystać z Foundation Models (Apple Intelligence)."
        }
        return "Na tym iPhonie działa wyłącznie model deterministyczny (offline)."
    }

    // MARK: - Private

    private static var isIPhone15ProOrNewer: Bool {
        let id = machineIdentifier
        guard id.hasPrefix("iPhone") else {
            // iPad / inne — Foundation Models tylko gdy system zgłosi dostępność; tu nie wymuszamy Pro.
            return false
        }
        let rest = id.dropFirst("iPhone".count)
        let parts = rest.split(separator: ",")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return false }

        // iPhone 16 (major 17) i nowsze — wszystkie modele z Apple Intelligence.
        if major >= 17 { return true }
        // iPhone 15 Pro = 16,1 · 15 Pro Max = 16,2 (nie 16,3/16,4 = zwykły 15 / Plus)
        if major == 16 { return minor == 1 || minor == 2 }
        return false
    }
}
