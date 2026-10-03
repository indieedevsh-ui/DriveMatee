import Foundation
import FoundationModels

/// CoreLM — strukturalne rozumienie naturalnego języka PL (ASR / tekst).
/// Rozróżnia akcje aplikacji, swobodną nawigację (start+cel) oraz uczciwe „nie umiem”.
enum CoreLM {
    @Generable(description: "Zrozumiana wypowiedź kierowcy Drive Mate")
    struct UnderstoodCommand {
        @Guide(description: "Rodzaj intencji")
        var action: Action

        @Guide(description: "Cel nawigacji albo zapytanie o miejsce/ulicę; puste gdy nie dotyczy")
        var destinationOrQuery: String

        @Guide(description: "Skąd startujemy przy nawigacji")
        var startMode: StartMode

        @Guide(description: "Adres/nazwa startu gdy startMode=customPlace; inaczej puste")
        var startPlace: String

        @Guide(description: "Pewność 0–1")
        var confidence: Double

        @Guide(description: """
            Gdy action=answer lub unsupported: krótka, uczciwa odpowiedź po polsku (1–2 zdania).
            Nie zmyślaj faktów mapy/ETA. Przy unsupported wprost powiedz, że Drive Mate tego jeszcze nie umie.
            Przy akcjach sterujących zostaw puste.
            """)
        var spokenReply: String

        @Generable
        enum Action {
            /// Nawigacja do miejsca (z opcjonalnym startem w tej samej wypowiedzi)
            case navigate
            /// Ocena korków / ruchu
            case traffic
            /// Informacja o ulicy / miejscu (MapKit)
            case streetInfo
            /// Głód / restauracja w pobliżu
            case findFood
            /// Pytanie ogólne — odpowiedź tekstowa bez zgadywania mapy
            case answer
            /// Prośba o funkcję spoza możliwości aplikacji
            case unsupported
            /// Brak sensu / pustka
            case none
        }

        @Generable
        enum StartMode {
            /// „z mojej lokalizacji / stąd / GPS”
            case myLocation
            /// Start z konkretnego adresu/miejsca (patrz startPlace)
            case customPlace
            /// Podano tylko cel — trzeba zapytać skąd
            case askUser
            /// Nie dotyczy nawigacji
            case none
        }
    }

    @MainActor
    static func makeUnderstandingSession() -> LanguageModelSession? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        return LanguageModelSession(
            model: model,
            instructions: """
                Jesteś CoreLM — ekspertem od rozumienia naturalnego polskiego w samochodzie (Drive Mate).
                Kierowca mówi swobodnie (ASR może mieć literówki). Wyodrębnij INTENCJĘ, nie parafrazuj na ślepo.

                Dostępne akcje aplikacji:
                - navigate — dojazd / trasa / „chcę dotrzeć”, sama nazwa miejsca jako cel
                - traffic — korki, ruch, utrudnienia
                - streetInfo — co to za ulica, info o miejscu (MapKit)
                - findFood — głód, restauracja, jedzenie w pobliżu
                - answer — pytanie ogólne / rozmowa; NIE wymyślaj mapy; wypełnij spokenReply
                - unsupported — prośba o coś, czego Drive Mate nie robi (pogoda poza mapą, rozmowy telefoniczne,
                  płatności, otwieranie innych appów, „włącz radio internetowe” itd.); spokenReply z odmową
                - none — pustka / szum

                Nawigacja — startMode:
                - myLocation gdy: „z mojej lokalizacji”, „z mojego punktu”, „stąd”, „zaczynam z GPS”, „from here”
                - customPlace gdy podano inny start (np. „z dworca”, „z ulicy Floriańskiej”) → startPlace
                - askUser gdy jest tylko cel (np. „Rynek Dębnicki”, „jedź na Wawel”) bez startu
                - none gdy to nie nawigacja

                Przykłady:
                - „Zaczynam z swojej lokalizacji i chcę dotrzeć do Rynku Dębnickiego”
                  → navigate, destinationOrQuery=\"Rynek Dębnicki\", startMode=myLocation
                - „Chciałbym dotrzeć do Wawelu z mojego punktu”
                  → navigate, destinationOrQuery=\"Wawel\", startMode=myLocation
                - „Rynek Dębnicki” / „zaprowadź mnie na rynek”
                  → navigate, startMode=askUser
                - „Jedź do Krakowa z dworca głównego”
                  → navigate, destinationOrQuery=\"Kraków\", startMode=customPlace, startPlace=\"Dworzec Główny\"
                - „jestem głodny” → findFood
                - „korki na Długiej” → traffic, destinationOrQuery=\"ulica Długa\"
                - „jaka jest stolica Francji?” → answer + spokenReply z faktą
                - „zadzwoń do mamy” → unsupported + spokenReply że nie umiesz dzwonić
                - „wylosuj trasę gdziekolwiek” → unsupported albo askUser tylko jeśli to realny cel — NIE losuj miejsca

                Zasady: nie wymyślaj miejsc; destinationOrQuery bez czasowników; confidence rzetelne.
                """
        )
    }

    @MainActor
    static func makeChatSession() -> LanguageModelSession? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        return LanguageModelSession(
            model: model,
            instructions: """
                Jesteś Drive Mate — asystent w aucie. Odpowiadasz po polsku, naturalnie, 1–3 zdania.

                Umiesz pomóc w: nawigacji Apple Maps, korkach, info o ulicy/miejscu, restauracjach w pobliżu.
                Jeśli prośba wykracza poza to — powiedz wprost: „Tego jeszcze nie umiem w Drive Mate.”
                NIGDY nie zmyślaj tras, ETA, adresów, korków ani wyników mapy.
                Nie losuj miejsc ani wyników. Jeśli nie wiesz — przyznaj się.
                Na luźne pytania (wiedza ogólna) odpowiadaj krótko i uczciwie.
                """
        )
    }

    @MainActor
    static func understand(
        _ transcript: String,
        session: LanguageModelSession
    ) async throws -> UnderstoodCommand {
        let prompt = """
        Zrozum naturalną wypowiedź kierowcy (PL, możliwie z ASR):
        „\(transcript)”

        Zwróć action, destinationOrQuery, startMode, startPlace, confidence, spokenReply.
        """
        let response = try await session.respond(
            to: prompt,
            generating: UnderstoodCommand.self
        )
        return response.content
    }

    @MainActor
    static func honestReply(
        to transcript: String,
        session: LanguageModelSession
    ) async throws -> String {
        let prompt = """
        Kierowca powiedział: „\(transcript)”

        Odpowiedz krótko po polsku. Jeśli to poza możliwościami Drive Mate — odmów wprost.
        Nie zmyślaj mapy, ETA ani miejsc.
        """
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func toDriveIntent(_ command: UnderstoodCommand) -> DriveIntent? {
        let dest = command.destinationOrQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let startPlace = command.startPlace.trimmingCharacters(in: .whitespacesAndNewlines)

        switch command.action {
        case .navigate:
            guard dest.count > 1 else { return nil }
            let origin: NavigateStartOrigin?
            switch command.startMode {
            case .myLocation:
                origin = .myLocation
            case .customPlace:
                origin = startPlace.count > 1 ? .place(startPlace) : nil
            case .askUser, .none:
                origin = nil
            }
            return .navigate(destination: dest, start: origin)

        case .traffic:
            return .traffic(query: dest.isEmpty ? nil : dest)

        case .streetInfo:
            return .streetInfo(query: dest.isEmpty ? nil : dest)

        case .findFood:
            return .findFood

        case .answer:
            let reply = command.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
            return .answer(replyHint: reply)

        case .unsupported:
            let reply = command.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unsupported(replyHint: reply.isEmpty
                ? "Tego jeszcze nie umiem zrobić w Drive Mate."
                : reply)

        case .none:
            return nil
        }
    }
}
