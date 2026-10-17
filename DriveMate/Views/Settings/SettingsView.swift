import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct NeonSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbWidth: CGFloat = 44
            let progress = CGFloat(value)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(height: 4)

                Capsule()
                    .fill(DriveMatePalette.neonGreen)
                    .frame(width: max(thumbWidth / 2, (width - thumbWidth) * progress + thumbWidth / 2), height: 5)
                    .shadow(color: DriveMatePalette.neonGreen.opacity(0.6), radius: 8)

                Color.clear
                    .frame(width: thumbWidth, height: 28)
                    .liquidGlassCapsule(.clear.interactive())
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1)
                    }
                    .offset(x: (width - thumbWidth) * progress)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let x = min(max(0, drag.location.x - thumbWidth / 2), width - thumbWidth)
                                value = Double(x / max(width - thumbWidth, 1))
                            }
                    )
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 36)
        .accessibilityValue(Text("\(Int(value * 100)) procent"))
    }
}

struct NeonToggle: View {
    @Binding var isOn: Bool

    private var trackColor: Color {
        isOn ? DriveMatePalette.limeRoute : Color(white: 0.38)
    }

    private var thumbColor: Color {
        isOn ? Color.black.opacity(0.82) : Color(white: 0.72)
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(trackColor)
                    .overlay {
                        Capsule()
                            .stroke(
                                isOn
                                    ? DriveMatePalette.limeRoute.opacity(0.9)
                                    : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    }
                    .frame(width: 64, height: 34)
                    .shadow(
                        color: isOn ? DriveMatePalette.limeRoute.opacity(0.55) : .clear,
                        radius: isOn ? 8 : 0
                    )

                Circle()
                    .fill(thumbColor)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: isOn ? 14 : -14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? "Włączone" : "Wyłączone"))
    }
}

struct SettingsCard<Content: View>: View {
    var isDark: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(isDark ? DriveMatePalette.cardFillDark : Color.white)
                    .shadow(color: .black.opacity(isDark ? 0.0 : 0.12), radius: 14, y: 6)
                    .shadow(color: .white.opacity(isDark ? 0.08 : 0.0), radius: 16, y: 0)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(isDark ? 0.08 : 0.6), lineWidth: 1)
                    }
            }
            .environment(\.settingsCardIsDark, isDark)
    }
}

private struct SettingsCardIsDarkKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var settingsCardIsDark: Bool {
        get { self[SettingsCardIsDarkKey.self] }
        set { self[SettingsCardIsDarkKey.self] = newValue }
    }
}

struct SettingsPrimaryText: ViewModifier {
    @Environment(\.settingsCardIsDark) private var isDark

    func body(content: Content) -> some View {
        content.foregroundStyle(isDark ? Color.white : Color.black.opacity(0.9))
    }
}

struct SettingsSecondaryText: ViewModifier {
    @Environment(\.settingsCardIsDark) private var isDark

    func body(content: Content) -> some View {
        content.foregroundStyle(isDark ? Color.white.opacity(0.75) : Color.black.opacity(0.55))
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: MusicLibraryService
    @ObservedObject var player: MusicPlayerService
    @ObservedObject var clips: ClipStorageService
    @ObservedObject private var fuel = FuelProfile.shared

    @State private var showImporter = false
    @State private var clipToPreview: RecordedClip?
    @ObservedObject private var musicSource = MusicSourceController.shared
    @State private var appleMusicAlert: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    driveMateEntryCard
                    soundCard
                    autoMuteCard
                    alwaysUseMyLocationCard
                    carModelCard
                    themeCard
                    recorderCard
                    clipsCard
                    musicUploadCard
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .background(settings.isDark ? Color.black : Color(white: 0.9))
            .navigationDestination(for: String.self) { key in
                if key == "driveMate" {
                    DriveMateSettingsView(settings: settings)
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.mp3, .mpeg4Movie, .movie, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                settings.musicSource = .local
                musicSource.select(.local)
                Task { await library.importFiles(from: urls) }
            case .failure(let error):
                library.importMessage = error.localizedDescription
            }
        }
        .onChange(of: settings.musicVolume) { _, newValue in
            player.volume = Float(newValue)
        }
        .sheet(item: $clipToPreview) { clip in
            NavigationStack {
                VideoPlayer(player: AVPlayer(url: clip.fileURL))
                    .ignoresSafeArea()
                    .navigationTitle(clip.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zamknij") { clipToPreview = nil }
                        }
                    }
            }
        }
        .alert("Muzyka", isPresented: Binding(
            get: { library.importMessage != nil },
            set: { if !$0 { library.importMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.importMessage = nil }
        } message: {
            Text(library.importMessage ?? "")
        }
        .alert("Spotify", isPresented: $musicSource.spotifyVoiceWarningVisible) {
            Button("Otwórz Spotify") {
                musicSource.dismissSpotifyWarning()
                musicSource.openSpotify()
            }
            Button("OK", role: .cancel) {
                musicSource.dismissSpotifyWarning()
            }
        } message: {
            Text("Wybrano Spotify. Funkcje głosowe związane z muzyką (pauza, następny utwór itd.) nie będą dostępne — zgodnie z polityką Spotify. Odtwarzanie działa w aplikacji Spotify.")
        }
        .alert("Apple Music", isPresented: Binding(
            get: { appleMusicAlert != nil },
            set: { if !$0 { appleMusicAlert = nil } }
        )) {
            Button("OK", role: .cancel) { appleMusicAlert = nil }
        } message: {
            Text(appleMusicAlert ?? "")
        }
    }

    private var driveMateEntryCard: some View {
        NavigationLink(value: "driveMate") {
            SettingsCard(isDark: settings.isDark) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Drive Mate")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .modifier(SettingsPrimaryText())
                        Text("Dane personalizacji, historia wizyt, preferencje tras i trening Hey Drive.")
                            .font(.system(size: 13, weight: .medium))
                            .modifier(SettingsSecondaryText())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DriveMatePalette.limeRoute)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var soundCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 18) {
                Text("SOUND")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .modifier(SettingsPrimaryText())
                NeonSlider(value: $settings.musicVolume)
            }
        }
    }

    private var autoMuteCard: some View {
        SettingsCard(isDark: settings.isDark) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Autowyciszacz")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Text("Ścisza muzykę gdy asystent mówi — nadal gra cicho w tle")
                        .font(.system(size: 13, weight: .medium))
                        .modifier(SettingsSecondaryText())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                NeonToggle(isOn: $settings.autoMuteEnabled)
            }
        }
    }

    private var alwaysUseMyLocationCard: some View {
        SettingsCard(isDark: settings.isDark) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Always Use My Location")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Text("Pomija pytanie o punkt startowy i zawsze zaczyna trasę z Twojej lokalizacji GPS.")
                        .font(.system(size: 13, weight: .medium))
                        .modifier(SettingsSecondaryText())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                NeonToggle(isOn: $settings.alwaysUseMyLocation)
            }
        }
    }

    private var carModelCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 14) {
                Text("MODEL AUTA")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .modifier(SettingsPrimaryText())
                Text("Potrzebny do dokładnego szacunku spalania i kosztu paliwa. Możesz też powiedzieć Drive Mate: „moje auto to Toyota Corolla”.")
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SettingsSecondaryText())
                    .fixedSize(horizontal: false, vertical: true)

                TextField("np. Toyota Corolla", text: $settings.carModel)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(settings.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )
                    .foregroundStyle(settings.isDark ? .white : .black)
                    .onChange(of: settings.carModel) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count >= 2 {
                            let est = CarFuelEstimator.litersPer100km(forModel: trimmed)
                            if est > 0 { settings.fuelConsumptionLPer100 = est }
                        }
                    }

                if let consumption = settings.resolvedFuelConsumption, consumption > 0 {
                    Text(String(format: "Szacunek: %.1f l/100 km · cena orient. %.2f zł/l",
                                consumption, fuel.pricePLNPerLiter))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DriveMatePalette.limeRoute)
                } else if !settings.carModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Brak spalania w litrach (np. EV) — koszt paliwa nie dotyczy.")
                        .font(.system(size: 12, weight: .medium))
                        .modifier(SettingsSecondaryText())
                }

                fuelControls
            }
        }
    }

    /// Bak i poziom paliwa — żeby „ile mi zostało” i „dowiozą mnie” miały odpowiedź.
    @ViewBuilder
    private var fuelControls: some View {
        let consumption = fuel.consumptionLPer100 ?? 0
        let range = fuel.rangeKm()

        VStack(alignment: .leading, spacing: 12) {
            Text("BAK I POZIOM PALIWA")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .modifier(SettingsSecondaryText())

            HStack {
                Text("Poziom")
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SettingsSecondaryText())
                Slider(
                    value: Binding(
                        get: { fuel.levelPercent },
                        set: { fuel.setLevelPercent($0) }
                    ),
                    in: 0...1
                )
                Text("\(Int((fuel.levelPercent * 100).rounded()))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DriveMatePalette.limeRoute)
                    .frame(width: 46, alignment: .trailing)
            }

            HStack {
                Text("Pojemność baku")
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SettingsSecondaryText())
                Spacer()
                Text(String(format: "%.0f l", fuel.tankCapacityLiters))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DriveMatePalette.limeRoute)
            }

            HStack {
                Text("Cena litra")
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SettingsSecondaryText())
                Spacer()
                Text(String(format: "%.2f zł", fuel.pricePLNPerLiter))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DriveMatePalette.limeRoute)
            }

            if consumption > 0 {
                Text(String(
                    format: "W baku %.1f l · zasięg ok. %.0f km · do pełnego %.0f zł",
                    fuel.litersInTank(), range ?? 0,
                    (fuel.tankCapacityLiters - fuel.litersInTank()) * fuel.pricePLNPerLiter
                ))
                .font(.system(size: 12, weight: .medium))
                .modifier(SettingsSecondaryText())

                Button {
                    fuel.refill()
                } label: {
                    Text("Zatankowałem — bak pełny")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(DriveMatePalette.limeRoute))
                }
            }

            Text("Paliwo odejmowane jest z baków po każdej zakończonej trasie na podstawie spalania.")
                .font(.system(size: 11, weight: .medium))
                .modifier(SettingsSecondaryText())
        }
    }

    private var themeCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 14) {
                Text("MOTYW")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .modifier(SettingsPrimaryText())
                HStack(spacing: 12) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Button {
                            settings.appearance = appearance
                        } label: {
                            Text(appearance.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(settings.appearance == appearance ? .black : (settings.isDark ? .white : .black.opacity(0.7)))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background {
                                    Capsule()
                                        .fill(settings.appearance == appearance ? DriveMatePalette.neonGreen : Color.primary.opacity(0.08))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recorderCard: some View {
        SettingsCard(isDark: settings.isDark) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECORDER")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Text("Włącza podgląd tylnej kamery i automatyczne klipy 10 s.")
                        .font(.system(size: 13, weight: .medium))
                        .modifier(SettingsSecondaryText())
                }
                Spacer()
                NeonToggle(isOn: $settings.recorderEnabled)
            }
        }
    }

    private var clipsCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("NAGRANE KLIPY")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Spacer()
                    if !clips.clips.isEmpty {
                        Button("Usuń wszystkie", role: .destructive) {
                            clips.deleteAll()
                        }
                        .font(.caption.bold())
                    }
                }

                if clips.clips.isEmpty {
                    Text("Brak nagranych klipów.")
                        .font(.subheadline)
                        .modifier(SettingsSecondaryText())
                } else {
                    ForEach(clips.clips) { clip in
                        HStack {
                            Button {
                                clipToPreview = clip
                            } label: {
                                HStack {
                                    Image(systemName: "film")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(clip.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(Int(clip.durationSeconds)) s")
                                            .font(.caption)
                                            .modifier(SettingsSecondaryText())
                                    }
                                }
                                .modifier(SettingsPrimaryText())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) {
                                clips.delete(clip)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var musicUploadCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 14) {
                Text("MUZYKA")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .modifier(SettingsPrimaryText())

                Text("Wybierz źródło odtwarzania. Sterowanie głosowe działa dla wgranych plików i Apple Music.")
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SettingsSecondaryText())

                // 1) Wgraj Muzykę
                musicSourceRow(
                    source: .local,
                    subtitle: "Pliki MP3/MP4 z urządzenia (AAC/M4A)."
                ) {
                    let already = settings.musicSource == .local
                    settings.musicSource = .local
                    musicSource.select(.local)
                    if already || library.tracks.isEmpty {
                        showImporter = true
                    }
                }

                if settings.musicSource == .local {
                    localTracksList
                }

                // 2) Apple Music
                musicSourceRow(
                    source: .appleMusic,
                    subtitle: musicSource.appleMusicAuthorized
                        ? "Połączono z Twoim Apple Music."
                        : "Połącz konto Apple Music (MusicKit)."
                ) {
                    settings.musicSource = .appleMusic
                    musicSource.select(.appleMusic)
                    Task {
                        let ok = await musicSource.requestAppleMusicIfNeeded()
                        if !ok, let msg = musicSource.appleMusicStatusMessage {
                            appleMusicAlert = msg
                        }
                    }
                }

                // 3) Spotify
                musicSourceRow(
                    source: .spotify,
                    subtitle: "Odtwarzanie w Spotify — bez komend głosowych muzyki."
                ) {
                    settings.musicSource = .spotify
                    musicSource.select(.spotify)
                }
            }
        }
    }

    private func musicSourceRow(
        source: MusicSource,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        let selected = settings.musicSource == source
        return Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .modifier(SettingsSecondaryText())
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? DriveMatePalette.limeRoute : .white.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(settings.isDark ? Color.white.opacity(selected ? 0.12 : 0.06) : Color.black.opacity(selected ? 0.08 : 0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? DriveMatePalette.limeRoute.opacity(0.7) : Color.clear,
                        lineWidth: 1.2
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var localTracksList: some View {
        if library.isImporting {
            HStack(spacing: 8) {
                ProgressView().tint(DriveMatePalette.limeRoute)
                Text("Importowanie…")
                    .font(.subheadline.weight(.semibold))
                    .modifier(SettingsSecondaryText())
            }
        }

        if library.tracks.isEmpty {
            Text("Brak utworów — wybierz „Wgraj Muzykę”, aby dodać pliki.")
                .font(.subheadline)
                .modifier(SettingsSecondaryText())
        } else {
            ForEach(library.tracks) { track in
                HStack {
                    Button {
                        settings.musicSource = .local
                        player.play(track: track)
                    } label: {
                        HStack {
                            Image(systemName: "music.note")
                            Text(track.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .modifier(SettingsPrimaryText())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) {
                        if player.currentTrack == track { player.pause() }
                        library.delete(track)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
