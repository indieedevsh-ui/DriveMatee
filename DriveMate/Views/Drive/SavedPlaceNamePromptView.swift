import SwiftUI
import MapKit

/// Okienko: wpisz nazwę szkoły/siłowni + podpowiedzi MapKit + Zapisz / Anuluj.
struct SavedPlaceNamePromptView: View {
    @ObservedObject var store: SavedPlaceNamePromptStore
    @StateObject private var autocomplete = PlaceAutocompleteService()
    @FocusState private var fieldFocused: Bool
    var onSaved: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(store.label.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DriveMatePalette.limeRoute)

                Text(titleText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                TextField(placeholder, text: $store.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
                    .onChange(of: store.draft) { _, value in
                        autocomplete.query = value
                        store.errorMessage = nil
                    }
                    .onSubmit { Task { await saveTapped() } }

                if let err = store.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                }

                if !autocomplete.suggestions.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(autocomplete.suggestions.prefix(6)) { suggestion in
                                Button {
                                    Task { await pickSuggestion(suggestion) }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(DriveMatePalette.limeRoute)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(suggestion.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .multilineTextAlignment(.leading)
                                            if !suggestion.subtitle.isEmpty {
                                                Text(suggestion.subtitle)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(.white.opacity(0.5))
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isSaving)

                                if suggestion.id != autocomplete.suggestions.prefix(6).last?.id {
                                    Divider().overlay(Color.white.opacity(0.12))
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    }
                }
            }
            .padding(22)

            HStack(spacing: 12) {
                Button {
                    store.cancel()
                    onCancel()
                } label: {
                    Text("Anuluj")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(store.isSaving)

                Button {
                    Task { await saveTapped() }
                } label: {
                    HStack(spacing: 8) {
                        if store.isSaving {
                            ProgressView().tint(.black)
                        }
                        Text("Zapisz")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.black.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(DriveMatePalette.limeRoute))
                }
                .buttonStyle(.plain)
                .disabled(store.isSaving || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 420)
        .liquidGlassRect(cornerRadius: 28, .regular)
        .onAppear {
            autocomplete.setUserRegion(
                coordinate: MapKitNavigationService.shared.location?.coordinate
            )
            fieldFocused = true
        }
        .onDisappear {
            autocomplete.clear()
        }
    }

    private var titleText: String {
        switch SavedPlacesStore.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching(store.label)) {
        case "dom", "home": return "Wpisz adres domu"
        case "praca", "work": return "Wpisz adres pracy"
        case "szkola", "school": return "Wpisz nazwę szkoły"
        default: return "Wpisz nazwę lub adres"
        }
    }

    private var placeholder: String {
        switch SavedPlacesStore.normalizeAliasKey(DriveIntentQueryHelpers.foldForMatching(store.label)) {
        case "dom", "home": return "np. ul. Floriańska 1, Kraków"
        case "praca", "work": return "np. Rondo Mogilskie…"
        case "szkola", "school": return "np. UKEN, AGH…"
        case "silownia", "gym": return "np. CityFit, Zdrofit…"
        default: return "Nazwa lub adres"
        }
    }

    private func pickSuggestion(_ suggestion: PlaceSuggestion) async {
        if let reply = await store.saveSuggestion(suggestion, using: autocomplete) {
            onSaved(reply)
        }
    }

    private func saveTapped() async {
        if let reply = await store.saveFromDraft(using: autocomplete) {
            onSaved(reply)
        }
    }
}
