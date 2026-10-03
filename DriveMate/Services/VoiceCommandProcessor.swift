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

        init(
            reply: String,
            source: Source,
            didApplySideEffect: Bool,
            awaitFurtherInput: Bool = false
        ) {
            self.reply = reply
            self.source = source
            self.didApplySideEffect = didApplySideEffect
            self.awaitFurtherInput = awaitFurtherInput
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

        // Oferta restauracji — anuluj / zatwierdź / potwierdź głosowo
        if let restaurantResult = await handleRestaurantOfferReply(cleaned) {
            return restaurantResult
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

        // 1) CoreLM najpierw — naturalny język, bez losowania wyników
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

                // Niska pewność / none — spróbuj uczciwej odpowiedzi zamiast zgadywać nawigację
                if understood.action == .answer || understood.action == .unsupported {
                    let hint = understood.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !hint.isEmpty {
                        return Result(reply: hint, source: .coreLM, didApplySideEffect: false)
                    }
                }
            } catch {
                // spadnij do parsera lokalnego
            }
        }

        // 2) Lokalny parser — znane wzorce PL (w tym start+cel)
        let local = DriveIntentParser.parse(cleaned)
        if case .unknown = local {
            // 3) Czat bez tools — uczciwa odpowiedź, bez zmyślania mapy
            if modelReady, let chatSession {
                do {
                    let text = try await CoreLM.honestReply(to: cleaned, session: chatSession)
                    if !text.isEmpty {
                        return Result(reply: text, source: .foundationModel, didApplySideEffect: false)
                    }
                } catch { /* poniżej */ }
            }

            // 4) Tool session tylko gdy wygląda na mapę — inaczej odmowa
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
                reply: "Mogę pomóc w nawigacji, korkach, info o ulicy albo restauracji. Czego potrzebujesz?",
                source: .localRouter,
                didApplySideEffect: false
            )
        }

        if let result = await fulfill(
            local,
            originalTranscript: cleaned,
            chatSession: chatSession,
            source: .localRouter
        ) {
            return result
        }
        return Result(reply: "Nie udało się wykonać polecenia.", source: .localRouter, didApplySideEffect: false)
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

            let awaitingStart = MapKitNavigationService.shared.pendingDestination != nil
            let awaitingFood: Bool = {
                if case .findFood = intent { return RestaurantOfferService.shared.isActive }
                return false
            }()
            let startedNav: Bool = {
                if case .navigate(_, let start) = intent { return start != nil && !awaitingStart }
                return false
            }()

            return Result(
                reply: answer,
                source: source,
                didApplySideEffect: isSideEffectIntent(intent) && (startedNav || (!awaitingStart && !awaitingFood)),
                awaitFurtherInput: awaitingStart || awaitingFood
            )
        }
    }

    private static func isSideEffectIntent(_ intent: DriveIntent) -> Bool {
        switch intent {
        case .navigate, .traffic, .streetInfo, .findFood: return true
        case .answer, .unsupported, .unknown: return false
        }
    }

    // MARK: - Restaurant

    private static func handleRestaurantOfferReply(_ text: String) async -> Result? {
        let offer = RestaurantOfferService.shared
        guard offer.isActive else { return nil }
        let lower = text.lowercased()

        if isCancelPhrase(lower) {
            offer.dismiss()
            MapComplianceStore.shared.clear()
            let cont = MapKitNavigationService.shared.mapState?.isNavigating == true
            return Result(
                reply: cont ? "Anulowano. Kontynuujemy obecną trasę." : "Anulowano wybór restauracji.",
                source: .localRouter,
                didApplySideEffect: false
            )
        }

        switch offer.phase {
        case .offering:
            if isConfirmPhrase(lower) {
                offer.beginAwaitingVoiceConfirm()
                return Result(
                    reply: offer.confirmationPrompt(),
                    source: .localRouter,
                    didApplySideEffect: false,
                    awaitFurtherInput: true
                )
            }
            return Result(
                reply: "Powiedz „zatwierdź” albo „anuluj”, albo użyj przycisków.",
                source: .localRouter,
                didApplySideEffect: false,
                awaitFurtherInput: true
            )

        case .awaitingVoiceConfirm:
            if isConfirmPhrase(lower) {
                let outcome = await offer.navigateToOfferIfConfirmed()
                return Result(
                    reply: outcome.reply,
                    source: .localRouter,
                    didApplySideEffect: outcome.started,
                    awaitFurtherInput: !outcome.started
                )
            }
            if isCancelPhrase(lower) {
                offer.dismiss()
                MapComplianceStore.shared.clear()
                let cont = MapKitNavigationService.shared.mapState?.isNavigating == true
                return Result(
                    reply: cont ? "OK, jedziemy dalej obecną trasą." : "OK, anulowano.",
                    source: .localRouter,
                    didApplySideEffect: false
                )
            }
            return Result(
                reply: offer.confirmationPrompt() + " Powiedz tak albo nie.",
                source: .localRouter,
                didApplySideEffect: false,
                awaitFurtherInput: true
            )

        case .idle:
            return nil
        }
    }

    private static func isConfirmPhrase(_ lower: String) -> Bool {
        let keys = [
            "tak", "zatwierdź", "zatwierdz", "ok", "okay", "dobra", "jasne",
            "jedź", "jedz", "chcę", "chce", "potwierdzam", "potwierdź", "potwierdz",
            "yes", "confirm", "go", "wybieram"
        ]
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return keys.contains(where: { trimmed == $0 || trimmed.hasPrefix($0 + " ") || trimmed.contains($0) })
    }

    private static func isCancelPhrase(_ lower: String) -> Bool {
        let keys = [
            "nie", "anuluj", "cancel", "pomiń", "pomin", "odrzuc", "odrzuć",
            "nie chcę", "nie chce", "nie teraz", "kontynuuj trasę", "kontynuuj trase"
        ]
        return keys.contains(where: { lower.contains($0) })
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
