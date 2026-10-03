import SwiftUI

/// Zakładka Drive Mate w Settings — dane personalizacji + trening Hey Drive.
struct DriveMateSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var memory = DriveMateMemoryStore.shared
    @StateObject private var wakeTrainer = WakeWordTrainer()

    @State private var confirmClearAll = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                introCard
                visitsCard
                routePrefsCard
                wakeTrainCard
                clearAllCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(settings.isDark ? Color.black : Color(white: 0.9))
        .navigationTitle("Drive Mate")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            wakeTrainer.cancel()
        }
        .alert("Usunąć wszystkie dane Drive Mate?", isPresented: $confirmClearAll) {
            Button("Anuluj", role: .cancel) {}
            Button("Usuń wszystko", role: .destructive) {
                memory.clearAllPersonalization()
                wakeTrainer.reset()
                wakeTrainer.cancel()
            }
        } message: {
            Text("Usunie historię wizyt (3 dni), wyuczone unikania ulic oraz profil wymowy Hey Drive.")
        }
    }

    private var introCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PERSONALIZACJA")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .modifier(SettingsPrimaryText())
                Text("Drive Mate dopasowuje trasy do Twojego stylu jazdy, pamięta miejsca z ostatnich 3 dni i uczy się, jak mówisz „Hey Drive”. Tutaj możesz to przejrzeć i usunąć.")
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SettingsSecondaryText())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var visitsCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("OSTATNIE MIEJSCA")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Spacer()
                    if !memory.visits.isEmpty {
                        Button("Wyczyść") { memory.clearVisits() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DriveMatePalette.limeRoute)
                    }
                }
                Text("Max 3 dni — głosowo: „Weź mnie tam gdzie pojechałem 2 dni temu”.")
                    .font(.system(size: 12, weight: .medium))
                    .modifier(SettingsSecondaryText())

                if memory.visits.isEmpty {
                    Text("Brak zapisanych wizyt.")
                        .font(.system(size: 13, weight: .medium))
                        .modifier(SettingsSecondaryText())
                } else {
                    ForEach(memory.visits) { visit in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(visit.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .modifier(SettingsPrimaryText())
                                Text(visit.dayLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .modifier(SettingsSecondaryText())
                            }
                            Spacer()
                            Button {
                                memory.removeVisit(id: visit.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        if visit.id != memory.visits.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private var routePrefsCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PREFERENCJE TRAS")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Spacer()
                    if !memory.avoidances.isEmpty {
                        Button("Wyczyść") { memory.clearAvoidances() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DriveMatePalette.limeRoute)
                    }
                }
                Text("Gdy ≥3 razy omijasz tę samą ulicę na trasie, Drive Mate następnym razem prowadzi „po Twojemu”.")
                    .font(.system(size: 12, weight: .medium))
                    .modifier(SettingsSecondaryText())
                    .fixedSize(horizontal: false, vertical: true)

                if memory.avoidances.isEmpty {
                    Text("Brak wyuczonych uników.")
                        .font(.system(size: 13, weight: .medium))
                        .modifier(SettingsSecondaryText())
                } else {
                    ForEach(memory.avoidances) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.avoidedStreetName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .modifier(SettingsPrimaryText())
                                Text("Cel: \(item.destinationTitle) · \(item.hitCount)×\(item.isActive ? " · aktywne" : "")")
                                    .font(.system(size: 12, weight: .medium))
                                    .modifier(SettingsSecondaryText())
                            }
                            Spacer()
                            Button {
                                memory.removeAvoidance(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        if item.id != memory.avoidances.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private var wakeTrainCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("HEY DRIVE — TRENING")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .modifier(SettingsPrimaryText())
                    Spacer()
                    if memory.wakeProfile.isTrained {
                        Button("Reset") {
                            memory.clearWakeProfile()
                            wakeTrainer.reset()
                            wakeTrainer.cancel()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DriveMatePalette.limeRoute)
                    }
                }
                Text("Powiedz „Hey Drive” trzy razy. AVAudioEngine nagrywa głos, SFSpeechRecognizer zamienia go na tekst — AI zapamiętuje Twoją wymowę.")
                    .font(.system(size: 12, weight: .medium))
                    .modifier(SettingsSecondaryText())
                    .fixedSize(horizontal: false, vertical: true)

                if memory.wakeProfile.isTrained, case .idle = wakeTrainer.phase {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wytrenowano")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DriveMatePalette.limeRoute)
                        ForEach(Array(memory.wakeProfile.samples.enumerated()), id: \.offset) { idx, sample in
                            Text("\(idx + 1). „\(sample)”")
                                .font(.system(size: 13, weight: .medium))
                                .modifier(SettingsSecondaryText())
                        }
                    }
                }

                Text(wakeTrainer.progressLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .modifier(SettingsPrimaryText())

                if case .recording = wakeTrainer.phase {
                    Text("Mów wyraźnie do mikrofonu iPhone’a. Pasek poniżej powinien się poruszać.")
                        .font(.system(size: 12, weight: .medium))
                        .modifier(SettingsSecondaryText())
                }

                // Poziom mikrofonu
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                        Capsule()
                            .fill(DriveMatePalette.limeRoute)
                            .frame(width: max(4, geo.size.width * wakeTrainer.audioLevel), height: 8)
                    }
                }
                .frame(height: 8)
                .opacity(isRecordingPhase ? 1 : 0.35)

                if !wakeTrainer.lastHeard.isEmpty {
                    Text("Słyszę: „\(wakeTrainer.lastHeard)”")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DriveMatePalette.limeRoute)
                }

                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < wakeTrainer.sampleCount ? DriveMatePalette.limeRoute : Color.white.opacity(0.15))
                            .frame(width: 10, height: 10)
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    if isRecordingPhase {
                        Button("Anuluj") {
                            wakeTrainer.cancel()
                            wakeTrainer.reset()
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .liquidGlassCapsule(.clear.interactive())
                    }

                    Button {
                        wakeTrainer.startTraining()
                    } label: {
                        Text(memory.wakeProfile.isTrained ? "Trenuj ponownie" : "Start treningu (3×)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.88))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(DriveMatePalette.limeRoute))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRecordingPhase)
                    .opacity(isRecordingPhase ? 0.45 : 1)
                }
            }
        }
    }

    private var isRecordingPhase: Bool {
        switch wakeTrainer.phase {
        case .recording, .processing: return true
        default: return false
        }
    }

    private var clearAllCard: some View {
        SettingsCard(isDark: settings.isDark) {
            VStack(alignment: .leading, spacing: 12) {
                Text("USUŃ DANE")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .modifier(SettingsPrimaryText())
                Text("Kasuje historię wizyt, preferencje tras i profil Hey Drive. Model auta w ustawieniach ogólnych zostaje.")
                    .font(.system(size: 12, weight: .medium))
                    .modifier(SettingsSecondaryText())
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    confirmClearAll = true
                } label: {
                    Text("Usuń wszystkie dane personalizacji")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
