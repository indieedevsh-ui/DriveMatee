import Foundation
@preconcurrency import CoreNFC
import Combine

/// Wielokrotne wykrywanie NFC **bez** systemowego „Ready to Scan”.
/// iOS sam dostarcza tag przy przybliżeniu (`onOpenURL` / user activity) — bez `NFCTagReaderSession`.
/// Arkusz skanu pojawia się tylko raz, gdy użytkownik w Ustawieniach zapisuje tryb na tagu.
@MainActor
final class NFCModeService: NSObject, ObservableObject {
    static let shared = NFCModeService()

    private static let registryKey = "nfcTagModeRegistry"

    @Published var pendingEmptyTagEncode = false
    @Published var presentedModeToast: TravelMode?
    /// Rośnie przy każdym skutecznym skanie trybu — UI może odpalić animację nawet przy tym samym trybie.
    @Published private(set) var modeScanEpoch: UInt = 0
    @Published private(set) var lastScannedMode: TravelMode?
    @Published private(set) var lastError: String?
    @Published private(set) var isSessionActive = false

    private var session: NFCTagReaderSession?
    private var toastTask: Task<Void, Never>?
    private var lastHandledKey: String?
    private var lastHandledAt: Date?
    /// Krótki debounce podwójnego zdarzenia — nie blokuje kolejnych przybliżeń.
    private let debounce: TimeInterval = 0.7

    private var pendingWriteMode: TravelMode?
    private var registry: [String: String] = [:]

    var isAvailable: Bool {
        NFCTagReaderSession.readingAvailable
    }

    override init() {
        super.init()
        registry = UserDefaults.standard.dictionary(forKey: Self.registryKey) as? [String: String] ?? [:]
        // Brak auto-sesji — nigdy nie pokazujemy „Ready to Scan” przy starcie apki.
    }

    // MARK: - Brak ciągłego nasłuchu (żadnego Ready to Scan)

    func startListening() {
        // Celowo puste: ciągły NFCTagReaderSession = systemowy arkusz „Ready to Scan”.
    }

    func stopListening() {
        // Anuluj tylko ewentualną sesję zapisu z Ustawień.
        if pendingWriteMode == nil {
            session?.invalidate()
            session = nil
            isSessionActive = false
        }
    }

    /// Ustawienia: wybór trybu w apce (bez skanu).
    func promptEncodeWithoutScan() {
        session?.invalidate()
        session = nil
        isSessionActive = false
        pendingWriteMode = nil
        pendingEmptyTagEncode = true
    }

    /// Po wyborze trybu — jednorazowy zapis NDEF (tu i tylko tu może być Ready to Scan).
    func encodeEmptyTag(as mode: TravelMode) {
        pendingEmptyTagEncode = false
        presentMode(mode, key: "encode:\(mode.rawValue)")

        guard isAvailable else {
            lastError = "To urządzenie nie obsługuje NFC."
            return
        }
        pendingWriteMode = mode
        beginWriteSession(alert: "Przybliż tag, aby zapisać: \(mode.title)")
    }

    func cancelEncodePrompt() {
        pendingEmptyTagEncode = false
        pendingWriteMode = nil
    }

    // MARK: - Odczyt systemowy (bez Ready to Scan) — wielokrotnie

    func handleOpenURL(_ url: URL) {
        if let mode = TravelMode.from(nfcURL: url) {
            presentMode(mode, key: "url:\(mode.rawValue):\(Int(Date().timeIntervalSince1970 * 10))")
        }
    }

    func handleUserActivity(_ activity: NSUserActivity) {
        if let url = activity.webpageURL {
            handleOpenURL(url)
        }
        let message = activity.ndefMessagePayload
        guard message.records.contains(where: { $0.typeNameFormat != .empty }) else { return }
        if let mode = Self.parseMode(from: message) {
            presentMode(mode, key: "ndef:\(mode.rawValue):\(Int(Date().timeIntervalSince1970 * 10))")
        }
    }

    // MARK: - Private

    private func saveMode(_ mode: TravelMode, forUID uid: String) {
        registry[uid] = mode.rawValue
        UserDefaults.standard.set(registry, forKey: Self.registryKey)
    }

    private func beginWriteSession(alert: String) {
        session?.invalidate()
        guard let newSession = NFCTagReaderSession(
            pollingOption: [.iso14443, .iso15693],
            delegate: self,
            queue: nil
        ) else {
            lastError = "Nie udało się uruchomić NFC."
            pendingWriteMode = nil
            return
        }
        newSession.alertMessage = alert
        session = newSession
        isSessionActive = true
        newSession.begin()
    }

    private func presentMode(_ mode: TravelMode, key: String) {
        // Debounce tylko identycznego, bardzo szybkiego dubla — nie „raz na otwarcie apki”.
        if let lastKey = lastHandledKey,
           lastKey.split(separator: ":").prefix(2).joined(separator: ":")
            == key.split(separator: ":").prefix(2).joined(separator: ":"),
           let last = lastHandledAt,
           Date().timeIntervalSince(last) < debounce {
            return
        }
        lastHandledKey = key
        lastHandledAt = Date()
        lastScannedMode = mode
        modeScanEpoch &+= 1
        presentedModeToast = mode
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            presentedModeToast = nil
        }
    }

    fileprivate func ndefTag(from tag: NFCTag) -> (any NFCNDEFTag)? {
        switch tag {
        case .miFare(let t): return t
        case .iso15693(let t): return t
        case .feliCa(let t): return t
        case .iso7816(let t): return t
        @unknown default: return nil
        }
    }

    fileprivate func tagUID(from tag: NFCTag) -> String? {
        let data: Data?
        switch tag {
        case .miFare(let t): data = t.identifier
        case .iso15693(let t): data = t.identifier
        case .feliCa(let t): data = t.currentIDm
        case .iso7816(let t): data = t.identifier
        @unknown default: data = nil
        }
        guard let data, !data.isEmpty else { return nil }
        return data.map { String(format: "%02X", $0) }.joined()
    }

    fileprivate static func parseMode(from message: NFCNDEFMessage) -> TravelMode? {
        for record in message.records {
            if let url = record.wellKnownTypeURIPayload(),
               let mode = TravelMode.from(nfcURL: url) {
                return mode
            }
            if let text = record.wellKnownTypeTextPayload().0 {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()
                if lower.hasPrefix("drivemate:") {
                    let raw = String(lower.dropFirst("drivemate:".count))
                    if let mode = TravelMode(rawValue: raw) { return mode }
                }
                if let url = URL(string: trimmed), let mode = TravelMode.from(nfcURL: url) {
                    return mode
                }
            }
        }
        return nil
    }

    fileprivate static func makeMessage(for mode: TravelMode) -> NFCNDEFMessage? {
        guard let uriRecord = NFCNDEFPayload.wellKnownTypeURIPayload(url: mode.nfcURI) else { return nil }
        return NFCNDEFMessage(records: [uriRecord])
    }
}

extension NFCModeService: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let ns = error as NSError
        Task { @MainActor in
            let benign = ns.domain == NFCErrorDomain && (
                ns.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue
                || ns.code == NFCReaderError.readerSessionInvalidationErrorSessionTimeout.rawValue
                || ns.code == NFCReaderError.readerSessionInvalidationErrorFirstNDEFTagRead.rawValue
            )
            if !benign {
                self.lastError = error.localizedDescription
            }
            self.pendingWriteMode = nil
            self.session = nil
            self.isSessionActive = false
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        if tags.count > 1 {
            session.invalidate(errorMessage: "Wykryto wiele tagów — zostaw jeden.")
            return
        }

        session.connect(to: tag) { error in
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }

            Task { @MainActor in
                let service = NFCModeService.shared
                guard let writeMode = service.pendingWriteMode else {
                    session.invalidate()
                    return
                }
                guard let ndef = service.ndefTag(from: tag) else {
                    session.invalidate(errorMessage: "Tag nie obsługuje NDEF.")
                    return
                }
                let uid = service.tagUID(from: tag)

                ndef.queryNDEFStatus { status, capacity, error in
                    if let error {
                        session.invalidate(errorMessage: error.localizedDescription)
                        return
                    }
                    Task { @MainActor in
                        guard status == .readWrite,
                              let message = Self.makeMessage(for: writeMode),
                              message.length <= capacity else {
                            session.invalidate(errorMessage: "Nie można zapisać na tym tagu.")
                            service.pendingWriteMode = nil
                            return
                        }
                        ndef.writeNDEF(message) { writeError in
                            Task { @MainActor in
                                if let writeError {
                                    session.invalidate(errorMessage: writeError.localizedDescription)
                                    service.pendingWriteMode = nil
                                    return
                                }
                                if let uid {
                                    service.saveMode(writeMode, forUID: uid)
                                }
                                session.alertMessage = "Zapisano: \(writeMode.title)"
                                session.invalidate()
                                service.pendingWriteMode = nil
                                service.presentMode(writeMode, key: "written:\(writeMode.rawValue)")
                            }
                        }
                    }
                }
            }
        }
    }
}
