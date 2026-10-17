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

        // Zamknij okienko umiejętności (przed anulowaniem asystenta)
        if DriveInfoCardStore.shared.isCapabilitiesCardActive, isDismissCardPhrase(cleaned) {
            DriveInfoCardStore.shared.dismiss()
            return Result(
                reply: "Zamykam.",
                source: .localRouter,
                didApplySideEffect: true
            )
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

        // Dojazd do celu — ukończyć trasę?
        if let arrivalResult = await handleArrivalConfirmReply(
            cleaned,
            chatSession: chatSession,
            modelReady: modelReady
        ) {
            return arrivalResult
        }

        // Oferta restauracji — anuluj / zatwierdź / naturalna mowa
        if let restaurantResult = await handleRestaurantOfferReply(
            cleaned,
            chatSession: chatSession,
            modelReady: modelReady
        ) {
            return restaurantResult
        }

        // Oferta sklepu (Żabka, Lewiatan…)
        if let storeResult = await handleStoreOfferReply(
            cleaned,
            chatSession: chatSession,
            modelReady: modelReady
        ) {
            return storeResult
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

        let folded = DriveIntentQueryHelpers.foldForMatching(cleaned)
        if DriveIntentParser.isNoiseOrFiller(folded) {
            return Result(
                reply: DriveIntentParser.unknownCommandReply,
                source: .localRouter,
                didApplySideEffect: false
            )
        }

        // Szybka ścieżka: lokalny parser PL (słownik + parafrazy semantyczne).
        let local = DriveIntentParser.parse(cleaned)
        switch local {
        case .unknown:
            break
        case .unsupported(let hint):
            return Result(
                reply: Self.shortRefusal(hint),
                source: .localRouter,
                didApplySideEffect: false
            )
        default:
            if let result = await fulfill(
                local,
                originalTranscript: cleaned,
                chatSession: chatSession,
                source: .localRouter
            ) {
                return result
            }
        }

        // CoreLM tylko dla wypowiedzi wyglądających na domenę Drive Mate — bez zgadywania.
        let inDomain = looksLikeMapCapability(cleaned) || looksLikeDriveDomain(folded)
        if inDomain, modelReady, let understandingSession {
            do {
                let understood = try await CoreLM.understand(cleaned, session: understandingSession)
                let minConfidence = minimumConfidence(for: understood.action)
                if understood.confidence >= minConfidence,
                   let intent = CoreLM.toDriveIntent(understood),
                   isSafeIntent(intent, transcript: cleaned),
                   !isHallucinatedSideEffect(intent, transcript: folded),
                   let result = await fulfill(
                       intent,
                       originalTranscript: cleaned,
                       chatSession: chatSession,
                       source: .coreLM
                   ) {
                    return result
                }

                // Odpowiedź tekstowa TYLKO gdy model sam uznał pytanie za domenowe (answer),
                // a nie gdy wciska navigate / findFood na losowe zdanie.
                if understood.action == .answer || understood.action == .unsupported {
                    let hint = understood.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
                    if understood.action == .unsupported {
                        return Result(
                            reply: Self.shortRefusal(hint),
                            source: .coreLM,
                            didApplySideEffect: false
                        )
                    }
                    if !hint.isEmpty {
                        return Result(reply: Self.stripUnsolicitedSkills(hint), source: .coreLM, didApplySideEffect: false)
                    }
                }

                // Ratunek tylko gdy wypada unsupported/none, a wypowiedź JEST z naszej domeny.
                if understood.action == .unsupported || understood.action == .none {
                    if let rescued = await rescueUnsupported(
                        understood,
                        transcript: cleaned,
                        chatSession: chatSession,
                        modelReady: modelReady
                    ) {
                        return rescued
                    }
                }
            } catch {
                // spadnij do odmowy
            }
        }

        // Narzędzia mapy — wyłącznie przy wyraźnym zapytaniu mapowym (nie przy „yhm”).
        if inDomain, modelReady, let toolSession, looksLikeMapCapability(cleaned) {
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
            } catch { /* spadnij dalej */ }
        }

        // Poza domeną / nierozpoznane — uczciwa odmowa, bez czatu zgadującego akcje.
        return Result(
            reply: DriveIntentParser.unknownCommandReply,
            source: .localRouter,
            didApplySideEffect: false
        )
    }

    /// CoreLM potrafi odmówić czegoś, co Drive Mate umie — wolimy wykonać, niż odmówić.
    ///
    /// Dotyczy przede wszystkim paliwa i ulicy: wcześniej pytanie o zasięg albo o obecną
    /// ulicę kończyło się „nie umiem tego zrobić”, mimo że dane były dostępne.
private static func rescueUnsupported(
            _ understood: CoreLM.UnderstoodCommand,
            transcript: String,
            chatSession: LanguageModelSession?,
            modelReady: Bool
        ) async -> Result? {
            guard modelReady, let chatSession else { return nil }

            // Bezpiecznik: nie każde niezrozumiane zdanie należy do naszej domeny.
            // Gdyby model wciskał akcję wypowiedzi typu „zadzwoń do mamy”, wykonalibyśmy
            // cudzą komendę — gorsze niż uczciwe „nie umiem”. Ratujemy tylko wtedy,
            // gdy wypowiedź wygląda na prośbę o dane z mapy / paliwa.
            guard looksLikeMapCapability(transcript) else { return nil }

            let known: [(action: CoreLM.UnderstoodCommand.Action, label: String)] = [
                (.fuelCost, "koszt paliwa na trasie"),
                (.fuelLevel, "poziom paliwa w baku"),
                (.fuelRange, "zasięg auta na obecnym paliwie"),
                (.nearestFuel, "najbliższa stacja paliw"),
                (.cheapestFuel, "stacja paliw pod kątem ceny"),
                (.streetInfo, "informacje o ulicy"),
                (.streetHistory, "historia ulicy"),
                (.whereAmI, "aktualny adres i ulica"),
                (.traffic, "ocena korków"),
                (.findFood, "najbliższa restauracja"),
                (.speedLimit, "limit prędkości"),
                (.navigate, "nawigacja do miejsca"),
                (.recenterMap, "wyśrodkowanie widoku mapy"),
                (.showCapabilities, "lista umiejętności Drive Mate"),
                (.musicPause, "sterowanie muzyką"),
                (.musicResume, "wznowienie muzyki"),
                (.musicNext, "następny utwór"),
                (.musicPrevious, "poprzedni utwór")
            ]

            // Dotąd lista możliwości była budowana przez `known.filter { $0.action == understood.action }`,
            // co dla `.unsupported` dawało pustą listę (brak odmiany `unsupported` w `known`),
            // a dla `.none` — listę WSZYSTKICH możliwości, po czym model był i tak
            // zmuszany do ponownego wypełnienia `.none`. Efekt: ratunek nigdy nie zadziałał.
            //
            // Teraz prosimy model o WYBRANIE jednej możliwości i wymuszamy TĘ akcję.
            let options = known.map(\.label).joined(separator: ", ")
            let pick = (try? await CoreLM.honestReply(
                to: """
                Kierowca powiedział: „\(transcript)”.
                Nie rozpoznałeś tego polecenia. Wybierz JEDNĄ pozycję z listy, która najbliżej pasuje do intencji kierowcy, i odpowiedz TYLKO jej nazwą, bez wyjaśnień:
                \(options)

                Jeśli żadna nie pasuje, odpowiedz dokładnie: NIC
                """,
                session: chatSession
            ))?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .lowercased() ?? ""

            guard !pick.isEmpty, pick != "nic" else { return nil }

            // Dopasuj odpowiedź z powrotem do akcji (model może skrócić etykietę).
            let matched = known.first { entry in
                pick.contains(entry.label)
                    || entry.label.contains(pick)
                    || pick.contains(String(entry.label.prefix(12)))
            }

            guard let chosen = matched else { return nil }

            // Wymuś wybraną akcję i niech model wypełni sloty.
            if let session = CoreLM.makeUnderstandingSession(),
               let retried = try? await CoreLM.understandForcedAction(
                   chosen.action,
                   transcript: transcript,
                   session: session
               ),
               let intent = CoreLM.toDriveIntent(retried),
               let result = await fulfill(
                   intent,
                   originalTranscript: transcript,
                   chatSession: chatSession,
                   source: .coreLM
               ) {
                return result
            }

            // Nie udało się wypełnić slotów — krótka odmowa, bez katalogu umiejętności.
            return Result(
                reply: DriveIntentParser.unknownCommandReply,
                source: .coreLM,
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
                reply: "Nie jestem pewien, o co chodzi. Mogę pomóc w trasie, korkach, ulicy, paliwie albo restauracji.",
                source: source,
                didApplySideEffect: false
            )

        case .unsupported(let hint):
            return Result(
                reply: Self.shortRefusal(hint),
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
            let awaitingStore: Bool = {
                if case .findNearestStore = intent { return StoreOfferService.shared.isActive }
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
                didApplySideEffect: isSideEffectIntent(intent) && (startedNav || (!awaitingStart && !awaitingFood && !awaitingStore && !awaitingGas) || intentNeedsSideEffect(intent)),
                awaitFurtherInput: awaitingStart || awaitingFood || awaitingStore || awaitingGas
            )
        }
    }

    private static func intentNeedsSideEffect(_ intent: DriveIntent) -> Bool {
        switch intent {
        case .cancelRoute, .restoreInterruptedRoute, .music, .nearestFuel,
             .findNearestStore, .navigateToPastVisit, .recenterMap, .showCapabilities,
             .tellTrivia:
            return true
        default: return false
        }
    }

    private static func isSideEffectIntent(_ intent: DriveIntent) -> Bool {
        switch intent {
        case .navigate, .traffic, .streetInfo, .streetHistory, .findFood, .findNearestStore,
             .tellTrivia, .cancelRoute, .restoreInterruptedRoute, .music, .speedLimit, .fuelCost,
             .fuelLevel, .fuelRange, .nearestFuel, .setCarModel, .whereAmI,
             .navigateToPastVisit, .setChromeTile, .recenterMap, .showCapabilities:
            return true
        case .cancelListening, .answer, .unsupported, .unknown:
            return false
        }
    }

    private static func minimumConfidence(for action: CoreLM.UnderstoodCommand.Action) -> Double {
        switch action {
        case .navigate, .pastVisit:
            return 0.72
        case .recenterMap, .showCapabilities, .chromeHide, .chromeShow,
             .musicPause, .musicResume, .musicNext, .musicPrevious,
             .cancelListening, .cancelRoute:
            return 0.45
        case .fuelCost, .fuelLevel, .fuelRange, .nearestFuel, .cheapestFuel,
             .whereAmI, .streetInfo, .streetHistory:
            return 0.55
        case .answer, .unsupported, .none:
            return 0.5
        default:
            return 0.6
        }
    }

    /// Odrzuć intencje, które wyglądają na zgadywanie (np. navigate → „widok”).
    private static func isSafeIntent(_ intent: DriveIntent, transcript: String) -> Bool {
        switch intent {
        case .navigate(let destination, _):
            guard destination.count > 1 else { return false }
            let destFold = DriveIntentQueryHelpers.foldForMatching(destination)
            if DriveIntentParser.isNoiseOrFiller(destFold) { return false }
            if DriveIntentParser.looksLikeUIOrCommandDestination(destination) {
                return false
            }
            let lower = DriveIntentQueryHelpers.foldForMatching(transcript)
            let uiHints = ["wysrodk", "centruj", "centrow", "ukryj kafelek", "pokaz kafelek"]
            if uiHints.contains(where: { lower.contains($0) }) { return false }
            // Nawigacja wymaga czasownika / prefiksu trasy — nie „yhm” ani luźne pytanie.
            let navHints = [
                "jedz", "nawig", "trasa", "trase", "zaprowadz", "zabierz", "dojazd",
                "dotrzec", "dojechac", "prowadz", "pokieruj", "kieruj", "wez mnie",
                "go to", "take me", "navigate", "drive to"
            ]
            guard navHints.contains(where: { lower.contains($0) })
                    || lower.hasPrefix("do ") || lower.hasPrefix("na ") else {
                return false
            }
            return true
        default:
            return true
        }
    }

    /// Model czasem „ratuje” losowe pytanie akcją poboczną — blokujemy.
    private static func isHallucinatedSideEffect(_ intent: DriveIntent, transcript: String) -> Bool {
        switch intent {
        case .navigate, .findFood, .findNearestStore, .nearestFuel, .navigateToPastVisit:
            return !looksLikeDriveDomain(transcript)
        default:
            return false
        }
    }

    /// Odmowa bez katalogu umiejętności (lista tylko po „co potrafisz”).
    private static func shortRefusal(_ hint: String) -> String {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return DriveIntentParser.unknownCommandReply }
        return stripUnsolicitedSkills(trimmed)
    }

    private static func stripUnsolicitedSkills(_ text: String) -> String {
        let lower = DriveIntentQueryHelpers.foldForMatching(text)
        let skillLaundry = [
            "umiem", "mogę", "moge", "potrafię", "potrafie",
            "nawigacj", "korki", "paliw", "restaurac", "muzyk"
        ]
        let mentionsCatalog = skillLaundry.filter { lower.contains($0) }.count >= 3
            || lower.contains("umiem nawig")
            || lower.contains("umie natomiast")
            || lower.contains("mogę zaprowadzić")
            || lower.contains("moge zaprowadzic")
        if mentionsCatalog {
            return DriveIntentParser.unknownCommandReply
        }
        return text
    }

    private static func looksLikeDriveDomain(_ lower: String) -> Bool {
        let keys = [
            "jedz", "trasa", "trase", "nawig", "kork", "ulic", "restaur", "glod",
            "paliw", "stacj", "tankow", "muzyk", "utwor", "piosenk", "adres",
            "gdzie jestem", "wysrodk", "centruj", "potrafisz", "umiesz", "dowiez",
            "zasieg", "ile mam", "co to za", "historia", "zakoncz", "anuluj",
            "przywróc", "przywroc", "pauza", "nastepn", "poprzedn",
            "zabka", "lewiatan", "empik", "sinsay", "biedronk", "sklep",
            "ciekawostk", "cos ciekawego"
        ]
        return keys.contains(where: { lower.contains($0) })
    }

    private static func isDismissCardPhrase(_ text: String) -> Bool {
        let lower = DriveIntentQueryHelpers.foldForMatching(text)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Nie kradnij „zamknij asystenta” / „wyłącz drive”.
        if lower.contains("asystent") || lower.contains("nasluch") || lower.contains("drive") {
            return false
        }
        let keys = [
            "zamknij", "zamknij okienko", "zamknij okno", "schowaj", "schowaj okienko",
            "ok zamknij", "juz", "dosc", "wystarczy", "dismiss", "close"
        ]
        return keys.contains(lower)
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

    // MARK: - Arrival confirm

    private static func handleArrivalConfirmReply(
        _ text: String,
        chatSession: LanguageModelSession?,
        modelReady: Bool
    ) async -> Result? {
        let arrival = ArrivalConfirmService.shared
        guard arrival.isActive else { return nil }
        let lower = text.lowercased()
        let decision = await resolveOfferDecision(
            text: text,
            lower: lower,
            chatSession: chatSession,
            modelReady: modelReady
        )
        switch decision {
        case .confirm:
            arrival.consumePromptForCompletion()
            guard let mapState = MapKitNavigationService.shared.mapState, mapState.isNavigating else {
                return Result(reply: "Trasa już nieaktywna.", source: .localRouter, didApplySideEffect: false)
            }
            DriveMateMemoryStore.shared.notifyTripEnded(
                destinationTitle: mapState.destinationTitle,
                destinationCoordinate: mapState.destinationCoordinate,
                subtitle: mapState.statusBanner ?? ""
            )
            let summary = mapState.endTripAndSummarize()
            NotificationCenter.default.post(
                name: .driveMateDidCancelRoute,
                object: nil,
                userInfo: [
                    "duration": summary.durationSeconds,
                    "distance": summary.distanceMeters,
                    "avgSpeed": summary.averageSpeedKmh,
                    "title": summary.destinationTitle as Any
                ]
            )
            return Result(
                reply: "Super — kończymy trasę.",
                source: .localRouter,
                didApplySideEffect: true
            )
        case .cancel:
            arrival.dismissKeepNavigating()
            return Result(
                reply: "OK, jedziemy dalej.",
                source: .localRouter,
                didApplySideEffect: false
            )
        case .unclear:
            return Result(
                reply: arrival.confirmationPrompt(),
                source: .localRouter,
                didApplySideEffect: false,
                awaitFurtherInput: true
            )
        }
    }

    // MARK: - Store

    private static func handleStoreOfferReply(
        _ text: String,
        chatSession: LanguageModelSession?,
        modelReady: Bool
    ) async -> Result? {
        let offer = StoreOfferService.shared
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
                    reply: cont ? "Anulowano. Kontynuujemy obecną trasę." : "Anulowano wybór sklepu.",
                    source: .localRouter,
                    didApplySideEffect: false
                )
            case .unclear:
                return Result(
                    reply: "Tak albo nie — jedziemy do tego sklepu?",
                    source: .localRouter,
                    didApplySideEffect: false,
                    awaitFurtherInput: true
                )
            }
        case .idle:
            return nil
        }
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
        let lower = DriveIntentQueryHelpers.foldForMatching(text)
        // Komendy UI mapy nie idą do narzędzi Foundation (findPlace) — lokalny router je ogarnia.
        if lower.contains("wysrodk") || lower.contains("centruj") || lower.contains("centrow")
            || lower.contains("recenter") {
            return false
        }
        if lower.contains("potrafisz") || lower.contains("umiesz") || lower.contains("umiejetnosc")
            || lower.contains("what can you") {
            return false
        }
        let keys = [
            "jedz", "trasa", "nawig", "korki", "korek", "ulic", "restaur",
            "glod", "jedzen", "obiad", "knajp", "dojazd", "zaprowadz",
            "miejsce", "paliw", "paliv", "spalan", "zuzyc", "stacja", "tankow",
            "koszt", "benzyn", "food", "fuel", "restaurant",
            // Nowe grupy: zasięg, bak, adres
            "bak", "bakie", "zuzy", "zasieg", "dowioze", "dowieziesz", "dojade",
            "rezerw", "adres", "lokalizacj", "gdzie jestem", "kod pocztowy",
            "miast", "powiat", "gmina", "skrzyz", "rondo", "osiedl", "dzielnic",
            // Parafrazy bez nazwy paliwa — „dowieziesz mnie”, „jak daleko dojadę”
            "starcz", "wystarcz", "zasieg", "litrow", "poziom", "bak ",
            "adres", "ulica", "historyczna", "charakterystyka"
        ]
        return keys.contains { lower.contains($0) }
    }

    private static func foundationPrompt(for command: String) -> String {
        """
        Kierowca: „\(command)”

        Użyj narzędzi (findPlace, assessTrafficRisk, streetInsight), gdy potrzebujesz REALNYCH danych mapy.
        Nawigacja: findPlace dla celu. NIE wywołuj planBestRoute, jeśli kierowca nie podał skąd startuje —
        wtedy potwierdź cel i zapytaj: „Skąd jedziemy — z Twojej lokalizacji, czy z innego miejsca?”
        Gdy start=moja lokalizacja jest w wypowiedzi — możesz planBestRoute po findPlace.

        Pytania o paliwo (ile paliwa, poziom baku, zasięg, dowieziesz mnie, koszt) obsłuż streetInsight/opisz to,
        czego nie umiesz — NIE mów „nie umiem”, bo umiesz. Nie zmyślaj ETA, miejsc ani wyników.
        Odmowę stosuj TYLKO dla: telefonów, SMS-ów, zakupów, rezerwacji, urządzeń domowych, gier, losowania miejsc.
        Przy odmowie: jedno krótkie zdanie, BEZ wymieniania co umiesz.
        Odpowiedź po polsku, 1–2 zdania.
        """
    }
}
