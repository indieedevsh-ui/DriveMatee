import Foundation
import FoundationModels

/// CoreLM — strukturalne rozumienie naturalnego języka PL (ASR / tekst).
/// Rozróżnia akcje aplikacji, swobodną nawigację (start+cel) oraz uczciwe „nie umiem”.
@available(iOS 26.0, *)
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
            Nie zmyślaj faktów mapy/ETA. Przy unsupported powiedz KRÓTKO że nie możesz tego zrobić (1 zdanie).
            NIE wymieniaj listy umiejętności — użytkownik pyta o nie osobno („co potrafisz”).
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
            /// Historia / ciekawostka o ulicy
            case streetHistory
            /// Głód / restauracja w pobliżu
            case findFood
            /// Najbliższy sklep sieci (Żabka, Lewiatan…) — destinationOrQuery = nazwa marki
            case findNearestStore
            /// Losowa ciekawostka (nie o konkretnej ulicy)
            case tellTrivia
            /// Ile czasu pozostało do końca aktywnej trasy
            case remainingTravelTime
            /// Zadaj łamigówkę; destinationOrQuery = math|fantasy|science|philosophy (opcjonalnie)
            case posePuzzle
            /// Powtórz ostatnią łamigówkę
            case repeatPuzzle
            /// Anuluj nasłuchiwanie asystenta
            case cancelListening
            /// Anuluj / zakończ aktywną trasę
            case cancelRoute
            /// Przywróć wcześniejszą / przerwaną trasę
            case restoreInterruptedRoute
            /// Muzyka w aplikacji: pauza
            case musicPause
            /// Muzyka: wznów / odpauzuj
            case musicResume
            /// Muzyka: następny utwór
            case musicNext
            /// Muzyka: poprzedni utwór
            case musicPrevious
            /// Limit / max prędkość na odcinku
            case speedLimit
            /// Kiedy / gdzie skręcić — następne rondo lub skrzyżowanie
            case nextTurnInfo
            /// Przelicz trasę: jedź prosto na następnym skrzyżowaniu
            case preferStraight
            /// Przelicz trasę: skręć w lewo (zamiast zaplanowanego)
            case preferLeft
            /// Przelicz trasę: skręć w prawo (zamiast zaplanowanego)
            case preferRight
            /// Szacunek kosztu paliwa na trasie
            case fuelCost
            /// Stan baku: ile litrów / procent, czy wystarczy
            case fuelLevel
            /// Zasięg: na ile wystarczy obecne paliwo i czy dowioże do celu
            case fuelRange
            /// Najbliższa stacja paliw
            case nearestFuel
            /// Stacje pod kątem ceny (bez live cen — lista najbliższych)
            case cheapestFuel
            /// „Gdzie jestem” — aktualna ulica i adres
            case whereAmI
            /// Zapis modelu auta użytkownika (do spalania)
            case setCarModel
            /// Nawigacja do miejsca z historii wizyt (N dni temu)
            case pastVisit
            /// Ukryj / pokaż kafelek UI (prędkościomierz, zegar, Drive…)
            case chromeHide
            case chromeShow
            /// Zwiększ przezroczystość kafelków (regular liquid glass ~35%)
            case tilesMoreTransparent
            /// Zmniejsz przezroczystość kafelków (regular liquid glass ~90%)
            case tilesLessTransparent
            /// Przeczytaj na głos widoczny kafelek / kartę / ofertę
            case readVisibleTile
            /// Wyśrodkuj mapę / widok na kierowcy (NIE nawigacja)
            case recenterMap
            /// Włącz nagrywanie
            case recordingOn
            /// Wyłącz nagrywanie
            case recordingOff
            /// Zmiana głośności; destinationOrQuery = „+” / „-” / „50” / „50%”
            case setVolume
            /// Tryb samochodowy
            case travelModeCar
            /// Tryb rowerowy
            case travelModeBike
            /// Włącz tryb AR
            case arOn
            /// Wyłącz tryb AR
            case arOff
            /// Włącz kompas (rower)
            case compassOn
            /// Wyłącz kompas
            case compassOff
            /// Pokaż listę umiejętności Drive Mate
            case showCapabilities
            /// Pobierz mapy offline (okienko z obszarem)
            case downloadOfflineMaps
            /// Zapisz bieżącą lokalizację jako dom
            case saveHome
            /// Zapisz bieżącą lokalizację jako pracę
            case saveWork
            /// Zaktualizuj dom (bieżąca lokalizacja albo destinationOrQuery = nowy adres)
            case updateHome
            /// Zaktualizuj pracę
            case updateWork
            /// Zapisz / zmień własne miejsce; destinationOrQuery = nazwa; startPlace = opcjonalny adres
            case saveNamedPlace
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
                - streetInfo — co to za ulica / info o miejscu / „powiedz o tej ulicy” / „co tutaj jest” (PRG, TERYT, mapa) — NIGDY unsupported
                - streetHistory — historia / ciekawostka o ulicy (Wikipedia + rejestry) — NIGDY unsupported
                - findFood — głód, restauracja, jedzenie, knajpa, lunch, „najbliższa restauracja”, „gdzie zjeść”
                - findNearestStore — „znajdź żabkę”, Lewiatan, Empik, Sinsay, Biedronka…; destinationOrQuery = marka
                - tellTrivia — „powiedz ciekawostkę” / „coś ciekawego” (losowa, NIE o ulicy)
                - remainingTravelTime — „ile jeszcze czasu”, „ile zostało do celu”, „kiedy dojadę”, ETA trasy — NIGDY unsupported
                - posePuzzle — „daj zagadkę”, „łamigówka”, „łamigłówka”, „zagadka”, „puzzle”, „quiz”, „coś do myślenia”, „zagadka matematyczna/fantasy/naukowa/filozoficzna”; destinationOrQuery = math|fantasy|science|philosophy albo puste — NIGDY unsupported
                - repeatPuzzle — „powtórz zagadkę”, „powtórz łamigówkę”, „jeszcze raz zagadkę” — NIGDY unsupported
                - cancelListening — „anuluj nasłuchiwanie”, „przestań słuchać”, wyłącz asystenta
                - cancelRoute — anuluj / zakończ aktywną trasę nawigacji
                - restoreInterruptedRoute — „przywróć wcześniejszą trasę” / przerwaną nawigację (NIE podsumowanie — tylko zmiana celu)
                - musicPause — pauza / zatrzymaj muzykę / stop (odtwarzacz w aplikacji) — NIGDY unsupported
                - musicResume — wznów / odpauzuj / włącz / puść muzykę — NIGDY unsupported
                - musicNext — następny / kolejny utwór / skip — NIGDY unsupported
                - musicPrevious — poprzedni utwór / cofnij utwór — NIGDY unsupported (to NIE jest restoreInterruptedRoute)
                - speedLimit — jaka max prędkość / limit na odcinku
                - nextTurnInfo — „kiedy mam skręcić”, „na jakim rondzie”, „gdzie skrecam”, „następny skręt” (pytanie, NIE zmiana trasy)
                - preferStraight — „chcę jechać prosto na następnym skrzyżowaniu”, „nie skręcaj, jedź prosto”
                - preferLeft — „chcę skręcić w lewo na następnym”, „zamiast w prawo jedź w lewo”
                - preferRight — „chcę w prawo na następnym skrzyżowaniu”
                - saveHome — TYLKO „tutaj jest mój dom” / „tu jest dom” (bieżąca lokalizacja GPS)
                - saveWork — TYLKO „tutaj jest moja praca” (GPS)
                - updateHome — „zmień mój dom” / „zmień dom na …”
                - updateWork — „zmień moją pracę”
                - saveNamedPlace — „zapamiętaj mój/moja Y” (Y=dom/praca/szkoła/…) → okienko (startPlace puste);
                  albo „tutaj jest moja szkoła” → GPS: destinationOrQuery=szkoła, startPlace=\"__here__\";
                  albo „moja szkoła to UKEN”: destinationOrQuery=szkoła, startPlace=UKEN
                - fuelCost — ile paliwa / spalanie / koszt przejazdu / „ile spalę” / „ile zapłacę za paliwo” / „koszt trasy” / „ile litrów na trasie”
                - fuelLevel — stan baku: „ile mam paliwa”, „poziom paliwa”, „ile procent”, „czy bak pełny”, „czy wystarczy mi paliwa”, „czy muszę zatankować”
                - fuelRange — zasięg: „na ile wystarczy”, „na ile kilometrów”, „jak daleko dojadę”, „dowieziesz mnie”, „czy dojadę na rezerwie”, „zasięg auta”
                - nearestFuel — najbliższa stacja paliw / tankowanie / „gdzie zatankować”
                - cheapestFuel — stacja pod kątem ceny (MapKit nie ma live cen) / „gdzie najtaniej”
                - whereAmI — „gdzie jestem”, „jaki jest mój adres”, „co to za ulica”, „jaka ulica tu jest”, „na jakiej ulicy stoję”, „w jakim mieście jestem”, „jaki kod pocztowy”
                - setCarModel — „moje auto to Toyota Corolla” / zapis modelu do spalania; destinationOrQuery = model
                - pastVisit — „tam gdzie pojechałem 2 dni temu”; destinationOrQuery = „2” lub „wczoraj”
                - chromeHide — ukryj kafelek UI; destinationOrQuery = nazwa (prędkościomierz / zegar / Drive / wyśrodkuj / nagrywanie). NIE ukrywaj: zakończ trasę, muzyka, skręt
                - chromeShow — pokaż / przywróć kafelek UI; destinationOrQuery = nazwa
                - tilesMoreTransparent — „zwiększ przezroczystość kafelków” / bardziej przezroczyste kafelki (regular ~35%)
                - tilesLessTransparent — „zmniejsz przezroczystość kafelków” / mniej przezroczyste / mocniejsze szkło (regular ~90%)
                - readVisibleTile — „przeczytaj mi to” / „przeczytaj kafelek” / „co tu pisze” — odczyt widocznej karty/oferty/skrętu
                - recenterMap — „wyśrodkuj widok”, „centruj mapę”, „wycentruj na mnie” — akcja mapy, NIGDY navigate
                - recordingOn / recordingOff — włącz / wyłącz nagrywanie (NIE chromeHide)
                - setVolume — głośność aplikacji; destinationOrQuery = „+”, „-”, „50”, „50%”, „głośniej”, „ciszej”
                - travelModeCar / travelModeBike — przełącz tryb samochodowy / rowerowy
                - arOn / arOff — włącz / wyłącz tryb AR (samochód, podczas nawigacji)
                - compassOn / compassOff — włącz / wyłącz kompas (rower, podczas nawigacji)
                - showCapabilities — „co potrafisz”, „co umiesz”, „jakie masz umiejętności”, „help”
                - downloadOfflineMaps — „pobierz mapy offline”, „ściągnij mapę offline”
                - answer — pytanie ogólne / rozmowa; NIE wymyślaj mapy; wypełnij spokenReply
                - unsupported — prośba o coś, czego Drive Mate nie robi; spokenReply = krótka odmowa BEZ listy umiejętności
                - none — pustka / szum

                Nawigacja — startMode:
                - myLocation gdy: „z mojej lokalizacji”, „z mojego punktu”, „stąd”, „zaczynam z GPS”, „from here”
                - customPlace gdy podano inny start (np. „z dworca”, „z ulicy Floriańskiej”) → startPlace
                - askUser gdy jest tylko cel (np. „Rynek Dębnicki”, „jedź na Wawel”) bez startu
                - none gdy to nie nawigacja

                Przykłady:
                - „Zaczynam z swojej lokalizacji i chcę dotrzeć do Rynku Dębnickiego”
                  → navigate, destinationOrQuery=\"Rynek Dębnicki\", startMode=myLocation
                - „Rynek Dębnicki” → navigate, startMode=askUser
                - „jestem głodny” / „najbliższa restauracja” / „gdzie zjeść” / „mam ochotę na obiad” → findFood
                - „znajdź najbliższą żabkę” / „lewiatan” / „empik w okolicy” → findNearestStore, destinationOrQuery=marka
                - „powiedz mi jakąś ciekawostkę” → tellTrivia
                - „anuluj nasłuchiwanie” → cancelListening
                - „anuluj trasę” → cancelRoute
                - „przywróć mi wcześniejszą trasę” / „wznów przerwaną trasę” → restoreInterruptedRoute
                - „pauza” / „zatrzymaj muzykę” → musicPause
                - „odpauzuj” / „wznów muzykę” → musicResume
                - „następny utwór” / „kolejna piosenka” → musicNext
                - „poprzedni utwór” / „cofnij utwór” → musicPrevious
                - „jaka jest maksymalna prędkość” → speedLimit
                - „kiedy mam skręcić” / „na jakim rondzie skręcam” / „gdzie mam skręcić” → nextTurnInfo
                - „chciałbym pojechać prosto na następnym skrzyżowaniu” → preferStraight
                - „jedź prosto zamiast skręcać” / „nie skręcaj” → preferStraight
                - „chcę skręcić w lewo na następnym” → preferLeft
                - „na następnym skrzyżowaniu w prawo” → preferRight
                - „tutaj jest mój dom” → saveHome
                - „tutaj jest moja praca” → saveWork
                - „tutaj jest moja szkoła” → saveNamedPlace, destinationOrQuery=szkoła, startPlace=__here__
                - „zapamiętaj mój dom” / „zapamiętaj moją pracę” / „zapamiętaj moją szkołę”
                  → saveNamedPlace, destinationOrQuery=dom|praca|szkoła, startPlace puste (okienko)
                - „zmień mój dom” / „zmień dom na Wawel” → updateHome (adres w destinationOrQuery)
                - „zapamiętaj moja szkoła to UKEN” → saveNamedPlace, destinationOrQuery=szkoła, startPlace=UKEN
                - „opowiedz historię tej ulicy” / „opowiedz coś o tej ulicy” / „powiedz coś o ulicy” → streetHistory
                - „co to za ulica” / „informacje o ulicy” → streetInfo (też z nutą historyczną)
                - „ile jeszcze czasu” / „ile zostało do celu” / „kiedy dojadę” → remainingTravelTime
                - „daj zagadkę” / „daj łamigówkę” / „łamigówka” / „łamigłówka” / „puzzle” → posePuzzle — NIGDY unsupported
                - „powtórz zagadkę” / „powtórz łamigówkę” → repeatPuzzle
                - „ile będzie kosztować paliwo” / „ile spalę” / „zużycie paliwa” / „koszt trasy” → fuelCost
                - „ile mam paliwa” / „poziom paliwa” / „czy wystarczy mi paliwa” / „czy muszę zatankować” → fuelLevel
                - „na ile wystarczy” / „jak daleko dojadę” / „dowieziesz mnie” / „zasięg auta” → fuelRange
                - „gdzie jest najbliższa stacja paliw” / „gdzie zatankować” → nearestFuel
                - „najtańsza stacja paliw” / „gdzie najtaniej zatankować” → cheapestFuel
                - „gdzie jestem” / „jaki jest mój adres” / „na jakiej ulicy jestem” / „co to za ulica” → whereAmI
                - „moje auto to Toyota Corolla” → setCarModel, destinationOrQuery=\"Toyota Corolla\"
                - „weź mnie tam gdzie pojechałem 2 dni temu” → pastVisit, destinationOrQuery=\"2\"
                - „ukryj prędkościomierz” → chromeHide, destinationOrQuery=\"prędkościomierz\"
                - „pokaż zegar” → chromeShow, destinationOrQuery=\"zegar\"
                - „zwiększ przezroczystość kafelków” / „bardziej przezroczyste kafelki” → tilesMoreTransparent
                - „zmniejsz przezroczystość kafelków” / „mniej przezroczyste kafelki” → tilesLessTransparent
                - „przeczytaj mi to” / „przeczytaj kafelek” / „co tu pisze” → readVisibleTile
                - „wyśrodkuj mi widok” / „centruj mapę” / „wycentruj na mnie” → recenterMap (NIGDY navigate do „widok”/„mapa”)
                - „włącz nagrywanie” → recordingOn; „wyłącz nagrywanie” → recordingOff
                - „zwiększ głośność” → setVolume, destinationOrQuery=\"+\"; „głośność na 50%” → setVolume, \"50%\"
                - „tryb rowerowy” → travelModeBike; „tryb samochodowy” → travelModeCar
                - „włącz AR” → arOn; „wyłącz kompas” → compassOff
                - „co potrafisz?” / „co umiesz?” / „jakie masz umiejętności?” → showCapabilities
                - „pobierz mapy offline” / „ściągnij mapę offline” → downloadOfflineMaps
                - „korki na Długiej” → traffic, destinationOrQuery=\"ulica Długa\"
                - „czy gdzieś mogę się spodziewać korków” / „szansa na korki na trasie” → traffic, destinationOrQuery puste
                - „zadzwoń do mamy” → unsupported, spokenReply=\"Nie mogę tego zrealizować.”
                - „wylosuj trasę gdziekolwiek” → unsupported — NIE losuj miejsca

                Zasady: nie wymyślaj miejsc; destinationOrQuery bez czasowników; confidence rzetelne.
                NIGDY nie używaj navigate gdy destinationOrQuery to słowo UI: widok, mapa, ekran, kafelek, zoom.
                Gdy niepewny między navigate a inną akcją — wybierz inną albo unsupported, NIE zgaduj celu.

                KRYTYCZNE — nie odmawiaj tego, co Drive Mate umie:
                Każde pytanie o PALIWO (ile paliwa, koszt, zasięg, poziom baku, stacja, „dowieziesz mnie”) ma swoją akcję powyżej.
                Każde pytanie o ULICĘ lub MIEJSCE (gdzie jestem, jaki adres, co to za ulica, historia, ciekawostka, TERYT, kod pocztowy)
                też. Jeśli nie jesteś pewien która — wybierz najbliższą z tych akcji i daj confidence 0.5, a NIE `unsupported`.
                `unsupported` zarezerwuj WYŁĄCZNIE dla: telefonowania do kogoś, wysyłania SMS, sterowania urządzeniami domowymi,
                zakupów, rezerwacji, gier, losowania miejsca, rozmów o pogodzie na dziś.
                Pytanie zrozumiane inaczej niż oczekiwano to nie powód do odmowy — to powód do `answer` lub `none`.

                Przykłady odmowy (TYLKO te):
                - „zadzwoń do mamy” / „wyślij SMS do Tomka” / „zamów pizzę” / „włącz światło w domu” / „wylosuj mi trasę gdziekolwiek”
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
                Jesteś Drive Mate — asystent w aucie. Odpowiadasz po polsku, naturalnie, 1–2 zdania.

                ZASADA: nie odmawiaj, bo pytanie jest sformułowane inaczej niż oczekiwano.
                Jeśli pytanie dotyczy nawigacji, ulicy, miejsca, paliwa, stacji, restauracji, korków, muzyki albo auta —
                odpowiedz na nie, używając tego co wiesz (poziom paliwa, zasięg, model auta, dane z podglądu).
                NIGDY nie odmawiaj z powodu samej formy wypowiedzi. Odmowa jest DOZWOLONA tylko dla:
                telefonów, SMS-ów, zakupów, rezerwacji, urządzeń domowych, gier i losowania miejsc.

                NIGDY nie zmyślaj tras, ETA, adresów, korków ani wyników mapy.
                Nie losuj miejsc. Jeśli nie rozumiesz albo nie umiesz — powiedz KRÓTKO „Nie mogę tego zrealizować.”
                NIE wymieniaj listy umiejętności przy odmowie. Listę podajesz TYLKO gdy kierowca pyta
                „co potrafisz” / „co umiesz” / „jakie masz umiejętności”.
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

    /// Ponowne rozpoznanie z narzuconą akcją — używane, gdy model najpierw odmówił,
    /// a sytuacja wygląda na coś, co Drive Mate umie. Wypełnia tylko sloty.
    @MainActor
    static func understandForcedAction(
        _ action: UnderstoodCommand.Action,
        transcript: String,
        session: LanguageModelSession
    ) async throws -> UnderstoodCommand {
        let prompt = """
        Wypowiedź kierowcy: „\(transcript)”
        Ustalono, że chodzi o akcję `\(action)`.
        Wypełnij destinationOrQuery (nazwa ulicy/miejsca/modelu auta albo puste), startMode, startPlace, confidence.
        spokenReply zostaw puste — odpowiedź wygeneruje aplikacja.
        """
        let response = try await session.respond(
            to: prompt,
            generating: UnderstoodCommand.self
        )
        var command = response.content
        command.action = action
        return command
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
            let destFold = DriveIntentQueryHelpers.foldForMatching(dest)
            if DriveIntentParser.isNoiseOrFiller(destFold) {
                return .unsupported(replyHint: DriveIntentParser.unknownCommandReply)
            }
            // Model czasem wciska „widok” / „mapę” jako cel — to UI, nie miejsce.
            if DriveIntentParser.looksLikeUIOrCommandDestination(dest) {
                if destFold.contains("widok") || destFold.contains("map") || destFold.contains("wysrodk") || destFold.contains("centr") {
                    return .recenterMap
                }
                return .unsupported(replyHint: DriveIntentParser.unknownCommandReply)
            }
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

        case .streetHistory:
            return .streetHistory(query: dest.isEmpty ? nil : dest)

        case .findFood:
            return .findFood

        case .findNearestStore:
            let brand = dest.isEmpty ? "sklep" : dest
            let mapped = DriveIntentParser.parse("znajdź najbliższy \(brand)")
            if case .findNearestStore(let q, let label) = mapped {
                return .findNearestStore(query: q, label: label)
            }
            return .findNearestStore(query: brand, label: brand)

        case .tellTrivia:
            return .tellTrivia

        case .remainingTravelTime:
            return .remainingTravelTime

        case .posePuzzle:
            let fold = DriveIntentQueryHelpers.foldForMatching(dest)
            let spokenFold = DriveIntentQueryHelpers.foldForMatching(command.spokenReply)
            let cat = DrivePuzzleService.category(fromFolded: fold)
                ?? DrivePuzzleService.category(fromFolded: spokenFold)
            return .posePuzzle(categoryRaw: cat?.rawValue)

        case .repeatPuzzle:
            return .repeatPuzzle

        case .cancelListening:
            return .cancelListening

        case .cancelRoute:
            return .cancelRoute

        case .restoreInterruptedRoute:
            return .restoreInterruptedRoute

        case .musicPause:
            return .music(.pause)

        case .musicResume:
            return .music(.resume)

        case .musicNext:
            return .music(.next)

        case .musicPrevious:
            return .music(.previous)

        case .speedLimit:
            return .speedLimit

        case .nextTurnInfo:
            return .nextTurnInfo

        case .preferStraight:
            return .preferManeuver(direction: .straight)

        case .preferLeft:
            return .preferManeuver(direction: .left)

        case .preferRight:
            return .preferManeuver(direction: .right)

        case .fuelCost:
            return .fuelCost

        case .fuelLevel:
            return .fuelLevel

        case .fuelRange:
            return .fuelRange

        case .nearestFuel:
            return .nearestFuel(preferCheapest: false)

        case .cheapestFuel:
            return .nearestFuel(preferCheapest: true)

        case .whereAmI:
            return .whereAmI

        case .setCarModel:
            let model = dest.isEmpty
                ? command.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
                : dest
            guard !model.isEmpty else { return nil }
            return .setCarModel(model)

        case .pastVisit:
            let raw = dest.lowercased()
            let days: Int
            if raw.contains("dziś") || raw.contains("dzis") || raw == "0" {
                days = 0
            } else if raw.contains("wczoraj") || raw == "1" {
                days = 1
            } else if raw.contains("przedwczoraj") {
                days = 2
            } else if let n = Int(raw.filter(\.isNumber)), (0...3).contains(n) {
                days = n
            } else {
                days = 1
            }
            return .navigateToPastVisit(daysAgo: days)

        case .chromeHide:
            let q = dest.isEmpty ? command.spokenReply : dest
            guard !q.isEmpty else { return nil }
            return .setChromeTile(tileQuery: q, visible: false)

        case .chromeShow:
            let q = dest.isEmpty ? command.spokenReply : dest
            guard !q.isEmpty else { return nil }
            return .setChromeTile(tileQuery: q, visible: true)

        case .tilesMoreTransparent:
            return .setTilesTransparency(moreTransparent: true)

        case .tilesLessTransparent:
            return .setTilesTransparency(moreTransparent: false)

        case .readVisibleTile:
            return .readVisibleTile

        case .recenterMap:
            return .recenterMap

        case .recordingOn:
            return .setRecording(enabled: true)

        case .recordingOff:
            return .setRecording(enabled: false)

        case .setVolume:
            let q = DriveIntentQueryHelpers.foldForMatching(dest.isEmpty ? command.spokenReply : dest)
            if q.contains("+") || q.contains("glosniej") || q.contains("zwieksz") || q.contains("up") {
                return .setVolume(level: nil, delta: 0.12)
            }
            if q.contains("-") || q.contains("ciszej") || q.contains("zmniejsz") || q.contains("scisz") || q.contains("down") {
                return .setVolume(level: nil, delta: -0.12)
            }
            if let pctRange = q.range(of: #"\d{1,3}"#, options: .regularExpression),
               let n = Double(q[pctRange]) {
                let level = n > 1 ? min(1, n / 100) : min(1, max(0, n))
                return .setVolume(level: level, delta: nil)
            }
            return .setVolume(level: nil, delta: 0.12)

        case .travelModeCar:
            return .setTravelMode(.car)

        case .travelModeBike:
            return .setTravelMode(.bike)

        case .arOn:
            return .setOverlayMode(ar: true, compass: nil)

        case .arOff:
            return .setOverlayMode(ar: false, compass: nil)

        case .compassOn:
            return .setOverlayMode(ar: nil, compass: true)

        case .compassOff:
            return .setOverlayMode(ar: nil, compass: false)

        case .showCapabilities:
            return .showCapabilities

        case .downloadOfflineMaps:
            return .downloadOfflineMaps

        case .saveHome:
            return .savePlace(slot: .home, customLabel: nil, replaceExisting: true, query: nil)

        case .saveWork:
            return .savePlace(slot: .work, customLabel: nil, replaceExisting: true, query: nil)

        case .updateHome:
            if dest.isEmpty { return .promptSavePlaceName(label: "Dom") }
            return .savePlace(slot: .home, customLabel: nil, replaceExisting: true, query: dest)

        case .updateWork:
            if dest.isEmpty { return .promptSavePlaceName(label: "Praca") }
            return .savePlace(slot: .work, customLabel: nil, replaceExisting: true, query: dest)

        case .saveNamedPlace:
            let name = dest.isEmpty
                ? command.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
                : dest
            guard !name.isEmpty else { return nil }
            let addr = command.startPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = SavedPlacesStore.canonicalLabel(for: name)
            let foldAddr = DriveIntentQueryHelpers.foldForMatching(addr)
            // GPS „tutaj jest …”
            if foldAddr == "__here__" || foldAddr == "here" || foldAddr == "gps" {
                let key = SavedPlacesStore.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching(label))
                switch key {
                case "dom", "home":
                    return .savePlace(slot: .home, customLabel: nil, replaceExisting: true, query: nil)
                case "praca", "work":
                    return .savePlace(slot: .work, customLabel: nil, replaceExisting: true, query: nil)
                default:
                    return .savePlace(slot: .custom, customLabel: label, replaceExisting: true, query: nil)
                }
            }
            // Bez nazwy → okienko („zapamiętaj mój dom / szkołę”)
            if addr.isEmpty {
                return .promptSavePlaceName(label: label)
            }
            let key = SavedPlacesStore.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching(label))
            switch key {
            case "dom", "home":
                return .savePlace(slot: .home, customLabel: nil, replaceExisting: true, query: addr)
            case "praca", "work":
                return .savePlace(slot: .work, customLabel: nil, replaceExisting: true, query: addr)
            default:
                return .savePlace(slot: .custom, customLabel: label, replaceExisting: true, query: addr)
            }

        case .answer:
            let reply = command.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
            return .answer(replyHint: reply)

        case .unsupported:
            let reply = command.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unsupported(replyHint: reply.isEmpty
                ? DriveIntentParser.unknownCommandReply
                : reply)

        case .none:
            return nil
        }
    }
}
