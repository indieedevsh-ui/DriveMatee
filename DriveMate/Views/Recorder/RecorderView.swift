import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var camera: CameraRecorderService

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        camera.attachPreviewLayer(view.videoPreviewLayer)
        camera.applyCurrentRotation()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        camera.attachPreviewLayer(uiView.videoPreviewLayer)
        camera.applyCurrentRotation()
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        // Preview znika — coordinator i tak trzyma weak ref.
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

struct RecorderView: View {
    @ObservedObject var camera: CameraRecorderService
    @ObservedObject var clips: ClipStorageService
    @ObservedObject var settings: AppSettings
    var isDark: Bool

    @State private var showLibrary = false
    @State private var previewClip: RecordedClip?

    var body: some View {
        ZStack {
            if !settings.recorderEnabled {
                disabledState
            } else if camera.permissionGranted {
                CameraPreviewView(session: camera.session, camera: camera)
                    .ignoresSafeArea()
                overlayControls
            } else {
                permissionState
            }

            if showLibrary {
                ClipsLibraryOverlay(
                    clips: clips,
                    isDark: isDark,
                    onSelect: { clip in
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            showLibrary = false
                        }
                        previewClip = clip
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            showLibrary = false
                        }
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .trailing)),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
                .zIndex(40)
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.78), value: showLibrary)
        .fullScreenCover(item: $previewClip) { clip in
            ClipPlayerSheet(clip: clip) {
                previewClip = nil
            }
        }
        .task {
            guard settings.recorderEnabled else { return }
            await camera.requestAccessAndConfigure()
        }
        .onChange(of: settings.recorderEnabled) { _, enabled in
            if enabled {
                Task { await camera.requestAccessAndConfigure() }
            } else {
                camera.stopContinuousRecording()
                camera.stopSession()
            }
        }
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                Spacer()
                if camera.isContinuousRecording {
                    Text("REC")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red, in: Capsule())
                        .padding(.trailing, 20)
                        .padding(.top, 16)
                }
            }

            Spacer()

            HStack(spacing: 14) {
                Spacer(minLength: 0)

                Button {
                    camera.toggleContinuousRecording(clipDuration: 10)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(camera.isContinuousRecording ? Color.white : Color.red)
                            .frame(width: 12, height: 12)
                        Text(camera.isContinuousRecording ? "Zatrzymaj Nagrywanie" : "Nagraj")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(camera.isContinuousRecording ? Color.red.opacity(0.92) : Color.red)
                    }
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.76)) {
                        showLibrary = true
                    }
                } label: {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .liquidGlassCircle(.clear.interactive())
                        .overlay { Circle().stroke(Color.white.opacity(0.3), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 28)
            .padding(.bottom, 24)
        }
    }

    private var disabledState: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(DriveMatePalette.neonGreen)
            Text("Recorder wyłączony")
                .font(.title2.bold())
            Text("Włącz go w Settings, aby korzystać z podglądu tylnej kamery i klipów 10 s.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color.black : Color(white: 0.92))
    }

    private var permissionState: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
            Text("Wymagany dostęp do kamery")
                .font(.title3.bold())
            Text(camera.lastError ?? "Zezwól na kamerę, aby zobaczyć podgląd.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Ponów prośbę") {
                Task { await camera.requestAccessAndConfigure() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DriveMatePalette.neonGreen)
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color.black : Color(white: 0.92))
    }
}

// MARK: - Sprężysty panel biblioteki

struct ClipsLibraryOverlay: View {
    @ObservedObject var clips: ClipStorageService
    var isDark: Bool
    var onSelect: (RecordedClip) -> Void
    var onClose: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 12)
    ]

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Text("Nagrania")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    if !clips.clips.isEmpty {
                        Button("Usuń wszystkie", role: .destructive) {
                            clips.deleteAll()
                        }
                        .font(.caption.weight(.semibold))
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .liquidGlassCircle(.clear.interactive())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                if clips.clips.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "Brak nagrań",
                        systemImage: "film.stack",
                        description: Text("Uruchom Nagraj, aby zapisywać klipy 10 s.")
                    )
                    .foregroundStyle(.white)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(clips.clips) { clip in
                                Button { onSelect(clip) } label: {
                                    ClipTile(clip: clip)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        clips.delete(clip)
                                    } label: {
                                        Label("Usuń", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .frame(maxWidth: 420)
            .frame(maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .liquidGlassRect(cornerRadius: 28, .regular)
                    .ignoresSafeArea()
            }
            .padding(.vertical, 10)
            .padding(.trailing, 10)
            .shadow(color: .black.opacity(0.4), radius: 24, x: -6)
        }
    }
}

struct ClipTile: View {
    let clip: RecordedClip
    @State private var thumb: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.35)
                        .overlay {
                            Image(systemName: "film")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(clip.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .task(id: clip.id) {
            thumb = await Self.generateThumbnail(url: clip.fileURL)
        }
    }

    private static func generateThumbnail(url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 360, height: 240)
                let time = CMTime(seconds: 0.3, preferredTimescale: 600)
                do {
                    let cg = try generator.copyCGImage(at: time, actualTime: nil)
                    continuation.resume(returning: UIImage(cgImage: cg))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct ClipPlayerSheet: View {
    let clip: RecordedClip
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: clip.fileURL))
                .ignoresSafeArea()
                .navigationTitle(clip.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Zamknij") { onClose() }
                    }
                }
        }
    }
}
