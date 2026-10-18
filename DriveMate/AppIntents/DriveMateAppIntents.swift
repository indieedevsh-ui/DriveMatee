import AppIntents
import Foundation

// MARK: - Entity (EN titles for Siri — Polish labels stay in-app)

struct SavedPlaceEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Saved place"
    static var defaultQuery = SavedPlaceEntityQuery()

    var id: UUID
    var englishTitle: String
    var englishSubtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: englishTitle),
            subtitle: LocalizedStringResource(stringLiteral: englishSubtitle)
        )
    }

    init(place: SavedPlace) {
        id = place.id
        englishTitle = place.siriTitle
        let addr = place.englishAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        englishSubtitle = addr.isEmpty ? place.address : addr
    }
}

struct SavedPlaceEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedPlaceEntity] {
        await MainActor.run {
            identifiers.compactMap { id in
                SavedPlacesStore.shared.place(id: id).map(SavedPlaceEntity.init)
            }
        }
    }

    func suggestedEntities() async throws -> [SavedPlaceEntity] {
        await MainActor.run {
            SavedPlacesStore.shared.places.map(SavedPlaceEntity.init)
        }
    }
}

extension SavedPlaceEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [SavedPlaceEntity] {
        await MainActor.run {
            // „my school” / „to school” / „szkoła” → exact resolve (bez luźnego contains).
            if let saved = SavedPlacesStore.shared.resolve(spokenQuery: string) {
                return [SavedPlaceEntity(place: saved)]
            }
            var fold = DriveIntentQueryHelpers.foldForMatching(string)
            for prefix in ["to my ", "to the ", "to ", "my ", "the ", "moja ", "moj "] {
                if fold.hasPrefix(prefix) {
                    fold = String(fold.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            guard fold.count >= 2 else { return [] }
            return SavedPlacesStore.shared.places
                .filter {
                    let en = DriveIntentQueryHelpers.foldForMatching($0.englishName)
                    let pl = DriveIntentQueryHelpers.foldForMatching($0.label)
                    return en == fold || pl == fold
                        || en.hasPrefix(fold) || pl.hasPrefix(fold)
                }
                .map(SavedPlaceEntity.init)
        }
    }
}

// MARK: - Start to saved place (App Shortcut + Siri phrases)

struct StartDriveMateSavedPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Navigate to saved place"
    static var description = IntentDescription("Starts navigation to Home, Work, or another saved place.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Place")
    var savedPlace: SavedPlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$savedPlace)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await DriveMateSiriBridge.startToSavedPlaceQueued(id: savedPlace.id)
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

// MARK: - Start to free-text destination (Siri asks “Where?”; String OK outside phrase slots)

struct StartDriveMateRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Start route"
    static var description = IntentDescription("Starts turn-by-turn navigation to a spoken or typed destination.")
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Destination",
        requestValueDialog: IntentDialog("Where should I navigate?")
    )
    var destination: String

    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$destination)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let raw = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw $destination.needsValueError("Where should I navigate?")
        }
        // „to my school” / Home / Work — najpierw zapisane miejsce (po id), potem MapKit.
        if let saved = SavedPlacesStore.shared.resolve(spokenQuery: raw) {
            let reply = await DriveMateSiriBridge.startToSavedPlaceQueued(id: saved.id)
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }
        if SavedPlacesStore.isKnownRoleAlias(raw) {
            let label = SavedPlacesStore.canonicalLabel(for: raw)
            return .result(
                dialog: IntentDialog(
                    stringLiteral: "I don't have \(label == "Szkoła" ? "School" : label) saved yet. Save it in DriveMate first."
                )
            )
        }
        // Oryginał do bridge — tam resolve + EN fallback pod MapKit.
        let reply = await DriveMateSiriBridge.startToDestinationQueued(raw)
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

// MARK: - End route

struct EndDriveMateRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "End route"
    static var description = IntentDescription("Ends or cancels the active DriveMate navigation route.")
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("End navigation")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await DriveMateSiriBridge.endActiveRouteQueued()
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

// MARK: - App Shortcuts (Siri phrases; entity/enum params only)

struct DriveMateAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDriveMateSavedPlaceIntent(),
            phrases: [
                "Navigate to \(\.$savedPlace) in \(.applicationName)",
                "Drive to \(\.$savedPlace) in \(.applicationName)",
                "Start route to \(\.$savedPlace) in \(.applicationName)",
                "Take me to \(\.$savedPlace) in \(.applicationName)",
                "Take me to my \(\.$savedPlace) in \(.applicationName)",
                "Navigate to my \(\.$savedPlace) in \(.applicationName)",
                "Jedź do \(\.$savedPlace) w \(.applicationName)",
                "Nawiguj do \(\.$savedPlace) w \(.applicationName)"
            ],
            shortTitle: "Navigate",
            systemImageName: "arrow.triangle.turn.up.right.diamond.fill"
        )
        AppShortcut(
            intent: StartDriveMateRouteIntent(),
            phrases: [
                "Start route in \(.applicationName)",
                "Navigate in \(.applicationName)",
                "Drive somewhere in \(.applicationName)",
                "Jedź w \(.applicationName)",
                "Nawigacja w \(.applicationName)"
            ],
            shortTitle: "Go",
            systemImageName: "map.fill"
        )
        AppShortcut(
            intent: EndDriveMateRouteIntent(),
            phrases: [
                "End navigation in \(.applicationName)",
                "Cancel route in \(.applicationName)",
                "Stop navigation in \(.applicationName)",
                "Zakończ trasę w \(.applicationName)",
                "Anuluj trasę w \(.applicationName)",
                "Zakończ nawigację w \(.applicationName)"
            ],
            shortTitle: "End route",
            systemImageName: "xmark.circle.fill"
        )
    }
}
