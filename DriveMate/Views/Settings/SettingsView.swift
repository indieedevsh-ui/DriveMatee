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

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .overlay {
                        Capsule()
                            .stroke(DriveMatePalette.neonGreenDeep.opacity(0.6), lineWidth: 1)
                    }
                    .frame(width: 64, height: 34)

                Capsule()
                    .fill(DriveMatePalette.neonGreen)
                    .frame(width: 34, height: 28)
                    .shadow(color: DriveMatePalette.neonGreen.opacity(0.7), radius: 8)
                    .offset(x: isOn ? -12 : 12)
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

    @State private var showImporter = false
    @State private var clipToPreview: RecordedClip?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                soundCard
                autoMuteCard
                themeCard
                recorderCard
                clipsCard
                musicUploadCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(settings.isDark ? Color.black : Color(white: 0.9))
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.mp3, .mpeg4Movie, .movie, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
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
                    Text("Wycisza muzykę gdy asystent chce poinformować kierowcę")
                        .font(.system(size: 13, weight: .medium))
                        .modifier(SettingsSecondaryText())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                NeonToggle(isOn: $settings.autoMuteEnabled)
            }
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

                Text("Wgraj pliki MP3 lub MP4. Pliki wideo są automatycznie konwertowane do audio (AAC/M4A — natywny format Apple; iOS nie udostępnia licencjonowanego enkodera MP3).")
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SettingsSecondaryText())

                Button {
                    showImporter = true
                } label: {
                    HStack {
                        if library.isImporting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(library.isImporting ? "Importowanie…" : "Wgraj muzykę")
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DriveMatePalette.neonGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(library.isImporting)

                if library.tracks.isEmpty {
                    Text("Brak utworów w bibliotece.")
                        .font(.subheadline)
                        .modifier(SettingsSecondaryText())
                } else {
                    ForEach(library.tracks) { track in
                        HStack {
                            Button {
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
    }
}
