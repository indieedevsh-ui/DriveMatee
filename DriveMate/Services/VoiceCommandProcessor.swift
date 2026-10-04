import Foundation
import FoundationModels

/// Pipeline: CoreLM (rozumienie NL) → wykonanie akcji / uczciwa odpowiedź.
/// Bez zgadywania wyników mapy; nawigacja może mieć start+cel w jednej wypowiedzi.
@MainActor
enum VoiceCommandProcessor {
    enum Source: String {
        case localRouter
        case coreLM
        case foundationModel
    }

    struct Result {
        let reply: String
        let source: Source
        let didApplySideEffect: Bool
        let awaitFurtherInput: Bool
        /// Zamknij asystenta (np. „anuluj nasłuchiwanie”).
        let dismissAssistant: Bool

        init(
            reply: String,
            source: Source,
            didApplySideEffect: Bool,
            awaitFurtherInput: Bool = false,
            dismissAssistant: Bool = false
        ) {
            self.reply = reply
            self.source = source
            self.didApplySideEffect = didApplySideEffect
            self.awaitFurtherInput = awaitFurtherInput
            self.dismissAssistant = dismissAssistant
        }
    }

    static func process(
        transcript: String,
        toolSession: LanguageModelSession?,
        understandingSession: LanguageModelSession?,
        chatSession: LanguageModelSession?,
        modelReady: Bool
    ) async -> Result {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return Result(reply: "Nie usłyszałem komendy.", source: .localRouter, didApplySideEffect: false)
        }

        // Anuluj nasłuchiwanie — przed innymi handlerami
        if isCancelListeningPhrase(cleaned) {
            return Result(
                reply: "OK, wyłączam.",
                source: .localRouter,
                didApplySideEffect: false,
                dismissAssistant: true
            )
        }

        // Oferta restauracji — anuluj / zatwierdź / naturalna mowa
        if let restaurantResult = await handleRestaurantOfferReply(
            cleaned,
            chatSession: chatSession,
            modelReady: modelReady
        ) {
            return restaurantResult
        }

        // Oferta stacji paliw
        if let gasResult = await handleGasStationOfferReply(
            cleaned,
            chatSession: chatSession,
            modelReady: modelReady
        ) {
            return gasResult
        }

        // Czekamy na punkt startowy po samym celu
        if MapKitNavigationService.shared.pendingDestination != nil {
            let outcome = await DriveIntentExecutor.completePendingStart(fromReply: cleaned)
            if outcome.reply.isEmpty {
                return Result(
                    reply: "Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?",
                    source: .localRouter,
                    didApplySideEffect: false,
                    awaitFurtherInput: true
                )
            }
            return Result(
                reply: outcome.reply,
                source: .localRouter,
                didApplySideEffect: outcome.started,
                awaitFurtherInput: !outcome.started
            )
        }

        // Szybka ścieżka: lokalny parser PL najpierw — bez czekania na CoreLM
        let local = DriveIntentParser.parse(cleaned)
        if case .unknown = local {
            // nic — spadnij do CoreLM / czatu
        } else if let result = await fulfill(
            local,
            originalTranscript: cleaned,
            chatSession: chatSession,
            source: .localRouter
        ) {
            return result
        }

        // CoreLM tylko gdy lokalny parser nie rozpoznał komendy
        if modelReady, let understandingSession {
            do {
                let understood = try await CoreLM.understand(cleaned, session: understandingSession)
                if understood.confidence >= 0.4,
                   let intent = CoreLM.toDriveIntent(understood) {
                    if let result = await fulfill(
                        intent,
                        originalTranscript: cleaned,
                        chatSession: chatSession,
                        source: .coreLM
                    ) {
                        return result
                    }
                }

                if understood.action == .answer || understood.action == .unsupported {
                    let hint = understood.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !hint.isEmpty {
                        return Result(reply: hint, source: .coreLM, didApplySideEffect: false)
                    }
                }
            } catch {
                // spadnij do czatu / odmowy
            }
        }

        // Czat bez tools — uczciwa odpowiedź, bez zmyślania mapy
        if modelReady, let chatSession {
            do {
                let text = try await CoreLM.honestReply(to: cleaned, session: chatSession)
                if !text.isEmpty {
                    return Result(reply: text, source: .foundationModel, didApplySideEffect: false)
                }
            } catch { /* poniżej */ }
        }

        // Tool session tylko gdy wygląda na mapę
        if modelReady, let toolSession, looksLikeMapCapability(cleaned) {
            do {
                let response = try await toolSession.respond(to: foundationPrompt(for: cleaned))
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let awaiting = MapKitNavigationService.shared.pendingDestination != nil
                    return Result(
                        reply: text,
                        source: .foundationModel,
                        didApplySideEffect: false,
                        awaitFurtherInput: awaiting
                    )
                }
            } catch { /* poniżej */ }
        }

        return Result(
            reply: "Mogę pomóc w nawigacji, korkach, info o ulicy, restauracji albo muzyce. Czego potrzebujesz?",
            source: .localRouter,
            didApplySideEffect: false
        )
    }

    // MARK: - Fulfill

    private static func fulfill(
        _ intent: DriveIntent,
        originalTranscript: String,
        chatSession: LanguageModelSession?,
        source: Source
    ) async -> Result? {
        switch intent {
        case .answer(let hint):
            if !hint.isEmpty {
                return Result(reply: hint, source: source, didApplySideEffect: false)
            }
            if let chatSession {
                do {
                    let text = try await CoreLM.honestReply(to: originalTranscript, session: chatSession)
                    if !text.isEmpty {
                        return Result(reply: text, source: .foundationModel, didApplySideEffect: false)
                    }
                } catch { /* ignore */ }
            }
            return Result(
                reply: "Nie jestem pewien. Mogę pomóc w trasie, korkach, ulicy albo restauracji.",
                source: source,
                didApplySideEffect: false
            )

        case .unsupported(let hint):
            return Result(
                reply: hint.isEmpty ? "Tego jeszcze nie umiem zrobić w Drive Mate." : hint,
                source: source,
                didApplySideEffect: false
            )

        case .unknown:
            return nil

        default:
            let answer = await DriveIntentExecutor.execute(intent)
            guard !answer.isEmpty else { return nil }

            if case .cancelListening = intent {
                return Result(
                    reply: answer.isEmpty ? "OK, wyłączam." : answer,
                    source: source,
                    didApplySideEffect: false,
                    dismissAssistant: true
                )
            }

            let awaitingStart = MapKitNavigationService.shared.pendingDestination != nil
            let awaitingFood: Bool = {
                if case .findFood = intent { return RestaurantOfferService.shared.isActive }
                return false
            }()
            let awaitingGas: Bool = {
                if case .nearestFuel = intent { return GasStationOfferService.shared.isActive }
                return false
            }()
            let startedNav: Bool = {
                if case .navigate(_, let start) = intent { return start != nil && !awaitingStart }
                return false
            }()

            return Result(
                reply: answer,
                source: source,
                didApplySideEffect: isSideEffectIntent(intent) && (startedNav || (!awaitingStart && !awaitingFood && !awaitingGas) || intentNeedsSideEffect(intent)),
                awaitFurtherInput: awaitingStart || awaitingFood || awaitingGas
            )
        }
    }

    private static func intentNeedsSideEffect(_ intent: DriveIntent) -> Bool {
        switch intent {
        case .cancelRoute, .restoreInterruptedRoute, .music, .nearestFuel, .navigateToPastVisit: return true
        default: return false
        }
    }

    private static func isSideEffectIntent(_ intent: DriveIntent) -> Bool {
        switch intent {
        case .navigate, .traffic, .streetInfo, .streetHistory, .findFood,
             .cancelRoute, .restoreInterruptedRoute, .music, .speedLimit, .fuelCost, .nearestFuel, .setCarModel,
             .navigateToPastVisit, .setChromeTile:
            return true
        case .cancelListening, .answer, .unsupported, .unknown:
            return false
        }
    }

    private static func isCancelListeningPhrase(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keys = [
            "anuluj nasłuch", "anuluj nasluch", "wyłącz nasłuch", "wylacz nasluch",
            "przestań słuchać", "przestan sluchac", "przestań słucha", "stop listening",
            "nie słuchaj", "nie sluchaj", "wyłącz się", "wylacz sie",
            "zamknij asystenta", "wyłącz drive", "wylacz drive", "spadaj"
        ]
        return keys.contains { lower.contains($0) }
    }

    // MARK: - Restaurant

    private static func handleRestaurantOfferReply(
        _ text: String,
        chatSession: LanguageModelSession?,
        modelReady: Bool
    ) async -> Result? {
        let offer = RestaurantOfferService.shared
        guard offer.isActive else { return nil }
        let lower = text.lowercased()

        switch offer.phase {
        case .offering, .awaitingVoiceConfirm:
            let decision = await resolveOfferDecision(
                text: text,
                lower: lower,
                chatSession: chatSession,
                modelReady: modelReady
            )
            switch decision {
            case .confirm:
                let outcome = await offer.navigateToOfferIfConfirmed()
                return Result(
                    reply: outcome.reply,
                    source: .localRouter,
                    didApplySideEffect: outcome.started,
                    awaitFurtherInput: !outcome.started
                )
            case .cancel:
                offer.dismiss()
                MapComplianceStore.shared.clear()
                let cont = MapKitNavigationService.shared.mapState?.isNavigating == true
                return Result(
                    reply: cont ? "Anulowano. Kontynuujemy obecną trasę." : "Anulowano wybór restauracji.",
                    source: .localRouter,
                    didApplySideEffect: false
                )
            case .unclear:
                return Result(
                    reply: "Jasne albo nie — jedziemy tam, czy anulujemy?",
                    source: .localRouter,
                    didApplySideEffect: false,
                    awaitFurtherInput: true
                )
            }

        case .idle:
            return nil
        }
    }

    private static func handleGasStationOfferReply(
        _ text: String,
        chatSession: LanguageModelSession?,
        modelReady: Bool
    ) async -> Result? {
        let offer = GasStationOfferService.shared
        guard offer.isActive else { return nil }
        let lower = text.lowercased()

        switch offer.phase {
        case .offering, .awaitingVoiceConfirm:
            let decision = await resolveOfferDecision(
                text: text,
                lower: lower,
                chatSession: chatSession,
                modelReady: modelReady
            )
            switch decision {
            case .confirm:
                let outcome = await offer.navigateToOfferIfConfirmed()
                return Result(
                    reply: outcome.reply,
                    source: .localRouter,
                    didApplySideEffect: outcome.started,
                    awaitFurtherInput: !outcome.started
                )
            case .cancel:
                offer.dismiss()
                MapComplianceStore.shared.clear()
                let cont = MapKitNavigationService.shared.mapState?.isNavigating == true
                return Result(
                    reply: cont ? "OK, jedziemy dalej obecną trasą." : "OK, anulowano.",
                    source: .localRouter,
                    didApplySideEffect: false
                )
            case .unclear:
                return Result(
                    reply: "Spoko albo nie — jedziemy na tę stację, czy anulujemy?",
                    source: .localRouter,
                    didApplySideEffect: false,
                    awaitFurtherInput: true
                )
            }

        case .idle:
            return nil
        }
    }

    private enum OfferDecision {
        case confirm, cancel, unclear
    }

    private static func resolveOfferDecision(
        text: String,
        lower: String,
        chatSession: LanguageModelSession?,
        modelReady: Bool
    ) async -> OfferDecision {
        if isCancelPhrase(lower) { return .cancel }
        if isConfirmPhrase(lower) { return .confirm }

        // Naturalna mowa — lekka klasyfikacja CoreLM gdy lokalne frazy nie złapały
        if modelReady, let chatSession {
            do {
                let label = try await CoreLM.honestReply(
                    to: """
                    Kierowca odpowiada na pytanie „czy jedziemy do zaproponowanego miejsca?”.
                    Jego wypowiedź: „\(text)”
                    Odpowiedz JEDNYM słowem dokładnie: TAK albo NIE albo NIEJASNE.
                    TAK = zgoda / spoko / jedźmy / pasuje / dobra.
                    NIE = anuluj / odpuść / nie chcę / zostaw.
                    """,
                    session: chatSession
                )
                let n = label
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    .lowercased()
                if n == "tak" || n.hasPrefix("tak ") { return .confirm }
                if n == "nie" || n.hasPrefix("nie ") { return .cancel }
                if n.contains("niejasne") { return .unclear }
                if n.contains("tak") { return .confirm }
                if n == "nie" || (n.contains("nie") && !n.contains("niejas")) { return .cancel }
            } catch { /* spadnij do unclear */ }
        }
        return .unclear
    }

    private static func isConfirmPhrase(_ lower: String) -> Bool {
        let trimmed = lower
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "  ", with: " ")

        let exact = [
            "tak", "ok", "okay", "okej", "okey", "dobra", "dobrze", "jasne", "yes", "yep", "yup",
            "go", "dawaj", "spoko", "spox", "git", "super", "pewnie", "pasuje", "zgoda",
            "lecimy", "jedziemy", "jedź", "jedz", "leć", "lec", "oczywiście", "oczywiscie",
            "jasna sprawa", "w porządku", "w porzadku", "czemu nie", "a czemu nie",
            "no", "noo", "no tak", "no spoko", "no dobra", "no dawaj", "no to tak",
            "to jedź", "to jedz", "to dawaj", "bierzemy", "bierz", "wybieram",
            "potwierdzam", "zatwierdzam", "akceptuję", "akceptuje"
        ]
        if exact.contains(trimmed) { return true }

        let positives = [
            "spoko", "spox", "zatwierdź", "zatwierdz", "potwierdz", "akceptuj",
            "jedź", "jedz", "jedziemy", "leć", "lecimy", "dawaj", "ruszaj", "startuj",
            "pasuje", "zgoda", "zgadzam", "pewnie", "jasne", "dobra", "dobrze",
            "super", "git", "brzmi dobr", "w porządku", "w porzadku", "czemu nie",
            "chcę tam", "chce tam", "chcę jechać", "chce jechac", "chcę jechac",
            "no to tak", "no spoko", "no dobra", "no to jedź", "no to jedz",
            "no to dawaj", "no to lec", "to jedźmy", "to jedzmy", "lecimy tam",
            "jedziemy tam", "bierzemy to", "wybieram", "confirm", "yes ", "okay",
            "oczywiście", "oczywiscie", "jasna sprawa", "może być", "moze byc",
            "niech będzie", "niech bedzie", "dawaj to", "bierz tę", "bierz te"
        ]
        if positives.contains(where: { trimmed == $0 || trimmed.hasPrefix($0 + " ") || trimmed.contains($0) }) {
            // Unikaj fałszywego „także” / „taki”
            if trimmed.hasPrefix("takż") || trimmed.hasPrefix("takz") || trimmed.hasPrefix("taki") {
                return false
            }
            return true
        }
        return false
    }

    private static func isCancelPhrase(_ lower: String) -> Bool {
        let trimmed = lower
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "  ", with: " ")

        let exact = [
            "nie", "nope", "anuluj", "cancel", "pomiń", "pomin", "odpuść", "odpusc",
            "zostaw", "olewamy", "olewam", "nara", "stop", "schowaj", "odrzuc", "odrzuć"
        ]
        if exact.contains(trimmed) { return true }

        let keys = [
            "anuluj", "cancel", "pomiń", "pomin", "odrzuc", "odrzuć", "odpuść", "odpusc",
            "nie chcę", "nie chce", "nie teraz", "nie potrzeb", "nie interes",
            "kontynuuj trasę", "kontynuuj trase", "wróć do tras", "wroc do tras",
            "zostaw", "olewamy", "olewam", "schowaj", "odznacz", "rezygnuj", "rezygnuję",
            "rezygnuje", "nie jedź", "nie jedz", "nie lec", "odwołaj", "odwolaj",
            "inna restaur", "inny lokal", "inna stacj"
        ]
        return keys.contains(where: { trimmed == $0 || trimmed.contains($0) })
    }

    private static func looksLikeMapCapability(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keys = [
            "jedź", "jedz", "trasa", "nawig", "korki", "korek", "ulic", "restaur",
            "głod", "glod", "mapa", "dojazd", "zaprowadź", "zaprowadz", "miejsce"
        ]
        return keys.contains { lower.contains($0) }
    }

    private static func foundationPrompt(for command: String) -> String {
        """
        Kierowca: „\(command)”

        Używaj narzędzi TYLKO gdy potrzebujesz realnych danych mapy (findPlace, assessTrafficRisk, streetInsight).
        Nawigacja: findPlace dla celu. NIE wywołuj planBestRoute jeśli kierowca nie podał skąd startuje —
        wtedy potwierdź cel i zapytaj: „Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?”
        Gdy start=moja lokalizacja jest w wypowiedzi — możesz planBestRoute po findPlace.
        Jeśli nie umiesz czegoś zrobić — powiedz wprost, NIE zmyślaj ETA, miejsc ani wyników.
        Odpowiedź po polsku, 1–2 zdania.
        """
    }
}
