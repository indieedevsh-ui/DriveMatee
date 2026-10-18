import Foundation
import Combine
import CoreLocation

/// Okienko „wpisz nazwę szkoły / siłowni…” po komendzie głosowej bez konkretnej nazwy.
@MainActor
final class SavedPlaceNamePromptStore: ObservableObject {
    static let shared = SavedPlaceNamePromptStore()

    @Published private(set) var isPresented = false
    /// Etykieta aliasu (Szkoła, Siłownia…).
    @Published private(set) var label: String = "Szkoła"
    @Published var draft = ""
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private init() {}

    func present(label: String) {
        self.label = SavedPlacesStore.canonicalLabel(for: label)
        draft = ""
        errorMessage = nil
        isSaving = false
        isPresented = true
    }

    func cancel() {
        isPresented = false
        draft = ""
        errorMessage = nil
        isSaving = false
    }

    @discardableResult
    func save(resolved: ResolvedPlace) async -> String {
        errorMessage = nil

        let slot = SavedPlacesStore.slot(forLabel: label)
        let displayLabel = slot == .custom ? label : slot.polishLabel
        let englishName = await PlaceNameTranslator.toEnglish(displayLabel)
        let addressParts = [resolved.title, resolved.subtitle].filter { !$0.isEmpty }
        let address = addressParts.joined(separator: ", ")
        let englishAddress = address.isEmpty ? "" : await PlaceNameTranslator.toEnglish(address)

        _ = SavedPlacesStore.shared.upsert(
            slot: slot,
            label: displayLabel,
            englishName: englishName,
            address: address,
            englishAddress: englishAddress,
            coordinate: resolved.coordinate
        )
        isPresented = false
        draft = ""
        return "Zapamiętałem: \(displayLabel) to \(resolved.title). Powiedz „jedź do \(displayLabel.lowercased())”."
    }

    @discardableResult
    func saveSuggestion(
        _ suggestion: PlaceSuggestion,
        using autocomplete: PlaceAutocompleteService
    ) async -> String? {
        isSaving = true
        errorMessage = nil
        draft = suggestion.title
        defer { isSaving = false }
        do {
            let resolved = try await autocomplete.resolve(suggestion)
            return await save(resolved: resolved)
        } catch {
            errorMessage = "Nie oznaczyłem tego miejsca — spróbuj innej nazwy."
            return nil
        }
    }

    @discardableResult
    func saveFromDraft(using autocomplete: PlaceAutocompleteService) async -> String? {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            errorMessage = "Wpisz nazwę."
            return nil
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let resolved: ResolvedPlace
            if let first = autocomplete.suggestions.first {
                resolved = try await autocomplete.resolve(first)
            } else {
                resolved = try await autocomplete.resolveQuery(q)
            }
            return await save(resolved: resolved)
        } catch {
            errorMessage = "Nie znalazłem „\(q)” na mapie."
            return nil
        }
    }
}
