import SwiftUI
import MapKit

/// Ekran startowy Drive (bez aktywnej nawigacji) — cel + start + autocomplete.
struct DriveIdleSetupView: View {
    @ObservedObject var location: LocationSpeedService
    @ObservedObject var recent: RecentPlacesStore
    @ObservedObject var assistant: DriveMateAssistant
    @ObservedObject var settings: AppSettings
    @ObservedObject private var interruptedRoutes = InterruptedRouteStore.shared
    var leadingChrome: CGFloat
    var onNavigationStarted: () -> Void
    var onVoiceModeChanged: ((Bool) -> Void)? = nil

    enum Phase: Equatable {
        case pickDestination
        case voiceListening
        case pickStart
        case typeStart
    }

    @StateObject private var autocomplete = PlaceAutocompleteService()
    @State private var phase: Phase = .pickDestination
    @State private var isEditingDestination = false
    @State private var destinationDraft = ""
    @State private var startDraft = ""
    @State private var selectedDestination: ResolvedPlace?
    @State private var destinationAppear = true
    @State private var voiceAppear = false
    @State private var startAppear = false
    @State private var isResolving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case destination, start }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if phase == .pickDestination {
                destinationPhase
                    .opacity(destinationAppear ? 1 : 0)
                    .offset(y: destinationAppear ? 0 : 12)
                    .allowsHitTesting(destinationAppear)
            }

            if phase == .voiceListening {
                voiceListeningPhase
                    .opacity(voiceAppear ? 1 : 0)
                    .offset(y: voiceAppear ? 0 : 10)
                    .allowsHitTesting(voiceAppear)
            }

            if phase == .pickStart || phase == .typeStart {
                startPhase
                    .opacity(startAppear ? 1 : 0)
                    .scaleEffect(startAppear ? 1 : 0.96)
            }

            if isResolving {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .padding(.leading, leadingChrome)
        .onAppear {
            autocomplete.setUserRegion(coordinate: location.coordinate)
            location.requestAccessAndStart()
        }
        .onChange(of: assistant.state) { _, newState in
            guard phase == .voiceListening else { return }
            // Nie wracaj do menu, gdy czekamy na punkt startowy
            if MapKitNavigationService.shared.pendingDestination != nil { return }
            if newState == .idle {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    guard phase == .voiceListening, assistant.state == .idle else { return }
                    guard MapKitNavigationService.shared.pendingDestination == nil else { return }
                    exitVoiceMode()
                }
            } else if case .unavailable = newState {
                exitVoiceMode()
            }
        }
        .alert("Drive Mate", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Destination

    private var destinationPhase: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            if isEditingDestination {
                destinationSearchBlock
                    .frame(maxWidth: 600)
            } else {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            isEditingDestination = true
                            focusedField = .destination
                        }
                    } label: {
                        Text("Where you wanna go")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 28)
                            .background { AnimatedDestinationPillBackground() }
                    }
                    .buttonStyle(.plain)

                    DictaphoneCircleButton(isActive: false) {
                        enterVoiceMode()
                    }
                }
                .frame(maxWidth: 600)
            }

            // Recently / przerwana trasa — wyrównane do lewej jak na koncepcie
            VStack(alignment: .leading, spacing: 12) {
                if let interrupted = interruptedRoutes.route {
                    Text("Przerwana trasa:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    HStack(spacing: 10) {
                        Button {
                            selectInterrupted(interrupted)
                        } label: {
                            Text(interrupted.shortLabel)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(DriveMatePalette.limeRoute)
                                }
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                                interruptedRoutes.clear()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 44, height: 44)
                                .liquidGlassCircle(.clear.interactive())
                                .overlay {
                                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Anuluj przerwaną trasę")
                    }
                } else if !recent.topFour.isEmpty {
                    Text("Recently:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(recent.topFour) { place in
                            Button {
                                Task { await selectRecent(place) }
                            } label: {
                                Text(place.shortLabel)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 10)
                                    .liquidGlassCapsule(.clear.interactive())
                                    .overlay {
                                        Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(isResolving)
                        }
                    }
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.trailing, 72) // lekko w lewo względem dyktafonu / centrum pastylki
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
    }

    // MARK: - Voice

    private var voiceListeningPhase: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            VoiceWaveVisualizer(level: assistant.audioLevel)
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)

            Text(assistant.transcript.isEmpty ? "Słucham…" : assistant.transcript)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 480)
                .animation(.easeOut(duration: 0.2), value: assistant.transcript)

            HStack(spacing: 16) {
                DictaphoneCircleButton(isActive: true) {
                    assistant.toggleListening()
                }

                Button("Anuluj") {
                    assistant.dismissAvatar()
                    exitVoiceMode()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
    }

    private func enterVoiceMode() {
        focusedField = nil
        isEditingDestination = false
        autocomplete.clear()
        onVoiceModeChanged?(true)

        // Jedna płynna wymiana faz — bez podwójnego DispatchQueue + ciężkich springów
        phase = .voiceListening
        voiceAppear = false
        withAnimation(.easeInOut(duration: 0.32)) {
            destinationAppear = false
            voiceAppear = true
        }
        // Summon po starcie animacji, żeby nie blokować pierwszego frame’a
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            assistant.summon()
        }
    }

    private func exitVoiceMode(animated: Bool = true) {
        onVoiceModeChanged?(false)
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                voiceAppear = false
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                phase = .pickDestination
                withAnimation(.easeInOut(duration: 0.3)) {
                    destinationAppear = true
                }
            }
        } else {
            voiceAppear = false
            phase = .pickDestination
            destinationAppear = true
        }
    }

    private var destinationSearchBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Where you wanna go", text: $destinationDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .destination)
                    .submitLabel(.search)
                    .onChange(of: destinationDraft) { _, value in
                        autocomplete.query = value
                    }
                    .onSubmit { Task { await confirmDestinationQuery() } }

                Button {
                    Task { await confirmDestinationQuery() }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(DriveMatePalette.neonGreen)
                }
                .buttonStyle(.plain)
                .disabled(destinationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 520)
            .background { AnimatedDestinationPillBackground() }

            if !autocomplete.suggestions.isEmpty {
                suggestionsList(forDestination: true)
                    .frame(maxWidth: 520)
            }
        }
    }

    // MARK: - Start

    private var startPhase: some View {
        VStack(spacing: 22) {
            if phase == .typeStart {
                if let dest = selectedDestination {
                    Text(dest.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                startSearchBlock
            } else {
                VStack(spacing: 16) {
                    Button {
                        Task { await startWithMyLocation() }
                    } label: {
                        Text("USE MY LOCATION")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .frame(maxWidth: 440)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 28)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.88))
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(DriveMatePalette.limeRoute.opacity(0.95), lineWidth: 1.6)
                            }
                            .shadow(color: DriveMatePalette.limeRoute.opacity(0.75), radius: 14, y: 0)
                            .shadow(color: DriveMatePalette.limeRoute.opacity(0.45), radius: 28, y: 0)
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving)

                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            phase = .typeStart
                            focusedField = .start
                            autocomplete.clear()
                        }
                    } label: {
                        Text("DIFFERENT")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 28)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.55))
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving)
                }
            }

            Button("Back") {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                    phase = .pickDestination
                    startAppear = false
                    destinationAppear = true
                    isEditingDestination = false
                    selectedDestination = nil
                    autocomplete.clear()
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.top, 4)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
    }

    private var startSearchBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Starting point", text: $startDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .start)
                    .submitLabel(.go)
                    .onChange(of: startDraft) { _, value in
                        autocomplete.query = value
                    }
                    .onSubmit { Task { await confirmStartQuery() } }

                Button {
                    Task { await confirmStartQuery() }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(DriveMatePalette.neonGreen)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .liquidGlassCapsule(.clear.interactive())
            .overlay { Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1) }

            if !autocomplete.suggestions.isEmpty {
                suggestionsList(forDestination: false)
            }
        }
    }

    private func suggestionsList(forDestination: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(autocomplete.suggestions) { suggestion in
                Button {
                    Task {
                        if forDestination {
                            await selectDestinationSuggestion(suggestion)
                        } else {
                            await selectStartSuggestion(suggestion)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if suggestion.id != autocomplete.suggestions.last?.id {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.clear)
                .liquidGlassRect(cornerRadius: 18, .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    // MARK: - Actions

    private func goToStartPhase() {
        focusedField = nil
        autocomplete.clear()
        // Bez mini-mapki po wyborze celu z Where you wanna go
        MapComplianceStore.shared.clear()

        // Always Use My Location — pomiń pytanie o start
        if settings.alwaysUseMyLocation {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                destinationAppear = false
            }
            Task { await startWithMyLocation() }
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
            destinationAppear = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            phase = .pickStart
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                startAppear = true
            }
        }
    }

    private func selectRecent(_ place: RecentPlace) async {
        selectedDestination = ResolvedPlace(
            title: place.title,
            subtitle: place.subtitle,
            coordinate: place.coordinate
        )
        goToStartPhase()
    }

    private func selectInterrupted(_ route: InterruptedRoute) {
        selectedDestination = ResolvedPlace(
            title: route.title,
            subtitle: route.subtitle,
            coordinate: route.coordinate
        )
        // Po wznowieniu — czyścimy „przerwaną”, żeby nie dublować
        interruptedRoutes.clear()
        goToStartPhase()
    }

    private func selectDestinationSuggestion(_ suggestion: PlaceSuggestion) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let resolved = try await autocomplete.resolve(suggestion)
            selectedDestination = resolved
            destinationDraft = resolved.title
            goToStartPhase()
        } catch {
            errorMessage = "Nie udało się znaleźć miejsca."
        }
    }

    private func confirmDestinationQuery() async {
        let q = destinationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            if let first = autocomplete.suggestions.first {
                let resolved = try await autocomplete.resolve(first)
                selectedDestination = resolved
            } else {
                selectedDestination = try await autocomplete.resolveQuery(q)
            }
            goToStartPhase()
        } catch {
            errorMessage = "Nie znalazłem „\(q)”."
        }
    }

    private func selectStartSuggestion(_ suggestion: PlaceSuggestion) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let start = try await autocomplete.resolve(suggestion)
            try await beginNavigation(from: start)
        } catch {
            errorMessage = "Nie udało się ustawić startu."
        }
    }

    private func confirmStartQuery() async {
        let q = startDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            let start: ResolvedPlace
            if let first = autocomplete.suggestions.first {
                start = try await autocomplete.resolve(first)
            } else {
                start = try await autocomplete.resolveQuery(q)
            }
            try await beginNavigation(from: start)
        } catch {
            errorMessage = "Nie znalazłem punktu startowego."
        }
    }

    private func startWithMyLocation() async {
        isResolving = true
        defer { isResolving = false }
        location.requestAccessAndStart()
        // Krótko poczekaj na fix GPS jeśli brak
        if location.coordinate == nil {
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        guard let coord = location.coordinate else {
            errorMessage = "Brak lokalizacji GPS. Włącz lokalizację lub wpisz start."
            return
        }
        do {
            try await beginNavigation(
                from: ResolvedPlace(title: "Moja lokalizacja", subtitle: "", coordinate: coord)
            )
        } catch {
            errorMessage = "Nie udało się wyznaczyć trasy."
        }
    }

    private func beginNavigation(from start: ResolvedPlace) async throws {
        guard let destination = selectedDestination else { return }
        do {
            _ = try await MapKitNavigationService.shared.planBestRoute(
                toLatitude: destination.coordinate.latitude,
                toLongitude: destination.coordinate.longitude,
                destinationName: destination.title,
                fromLatitude: start.coordinate.latitude,
                fromLongitude: start.coordinate.longitude
            )
            recent.add(
                title: destination.title,
                subtitle: destination.subtitle,
                coordinate: destination.coordinate
            )
            onNavigationStarted()
        } catch NavigationError.disclaimerRequired {
            NotificationCenter.default.post(name: .driveMateNeedsNavEULA, object: nil)
            errorMessage = "Zaakceptuj warunki nawigacji, aby wystartować trasę."
        }
    }

}

/// Animowany subtelny gradient w pastylce „Where you wanna go”.
struct AnimatedDestinationPillBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.04))
            .background {
                Capsule(style: .continuous)
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(red: 0.15, green: 0.55, blue: 0.35).opacity(0.55),
                                Color(red: 0.55, green: 0.12, blue: 0.22).opacity(0.5),
                                Color(red: 0.35, green: 0.18, blue: 0.55).opacity(0.55),
                                Color(red: 0.12, green: 0.35, blue: 0.55).opacity(0.45),
                                Color(red: 0.15, green: 0.55, blue: 0.35).opacity(0.55)
                            ],
                            center: .center,
                            angle: .degrees(Double(phase))
                        )
                    )
                    .blur(radius: 10)
                    .opacity(0.85)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .liquidGlassCapsule(.clear)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    phase = 360
                }
            }
    }
}
