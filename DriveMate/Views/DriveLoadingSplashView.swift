import SwiftUI

/// Splash ładowania — czarne tło, limonkowe auto, kamyczki + wibracje; na koniec realne przyspieszenie w prawą krawędź.
struct DriveLoadingSplashView: View {
    var onFinished: () -> Void = {}

    @State private var startedAt = Date()
    @State private var contentOpacity: Double = 1
    @State private var didFinish = false

    /// Jazda „w miejscu” z kamyczkami.
    private let driveSeconds: Double = 2.05
    /// Wyjazd z mocnym ease-in (przyspieszenie).
    private let exitSeconds: Double = 0.72

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let exitT = max(0, min(1, (elapsed - driveSeconds) / exitSeconds))
            // Mocne przyspieszenie: wolno na starcie, potem gwałtownie w prawo
            let exitProgress = CGFloat(pow(exitT, 2.85))

            ZStack {
                Color.black.ignoresSafeArea()

                MinimalLimeCarCanvas(
                    elapsed: elapsed,
                    exitProgress: exitProgress,
                    exitLinear: CGFloat(exitT)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(contentOpacity)

                VStack {
                    Spacer()
                    Text("Drive Mate")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(DriveMatePalette.limeRoute.opacity(0.85))
                        .padding(.bottom, 36)
                }
                .opacity(contentOpacity * Double(1 - exitProgress))
            }
            .onChange(of: exitT) { _, t in
                guard !didFinish, t >= 1 else { return }
                didFinish = true
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.25)) {
                        contentOpacity = 0
                    }
                    try? await Task.sleep(nanoseconds: 260_000_000)
                    onFinished()
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Canvas

private struct MinimalLimeCarCanvas: View {
    var elapsed: Double
    /// Zakrzywione przyspieszenie (0…1) — pozycja X.
    var exitProgress: CGFloat
    /// Liniowy postęp wyjścia — do intensywności particlesów.
    var exitLinear: CGFloat

    private var lime: Color { DriveMatePalette.limeRoute }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let roadY = h * 0.58

            // Prędkość „świata” — rośnie przy starcie wyjazdu
            let scrollSpeed = 70.0 + Double(exitProgress) * 520.0
            let world = elapsed * scrollSpeed

            // Linia drogi
            var road = Path()
            road.move(to: CGPoint(x: 0, y: roadY + 36))
            road.addLine(to: CGPoint(x: w, y: roadY + 36))
            ctx.stroke(road, with: .color(lime.opacity(0.12)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Kreski drogi
            var dx = -((world * 0.85).truncatingRemainder(dividingBy: 48)) - 20
            while dx < w + 40 {
                let dash = RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .path(in: CGRect(x: dx, y: roadY + 32, width: 22, height: 3))
                ctx.fill(dash, with: .color(lime.opacity(0.22)))
                dx += 48
            }

            // Kamyczki (okresowo na torze)
            let pebbleGap = 210.0
            let firstPebble = floor(world / pebbleGap) * pebbleGap
            var bumpStrength: Double = 0
            for i in 0..<6 {
                let worldPos = firstPebble + Double(i) * pebbleGap + 40
                let sx = CGFloat(worldPos - world) + w * 0.15
                guard sx > -40, sx < w + 40 else { continue }
                drawPebbleCluster(ctx, at: CGPoint(x: sx, y: roadY + 28), lime: lime)

                // Trafienie pod koła auta (auto ~0.38 szerokości podczas jazdy)
                let carProbeX = w * 0.38 + (w * 0.62 + 90) * exitProgress
                let dist = abs(Double(sx) - Double(carProbeX))
                if dist < 28 {
                    let hit = 1 - dist / 28
                    bumpStrength = max(bumpStrength, hit * hit)
                }
            }

            // Lekkie wibracje + mocniejsze na kamyczkach
            let micro =
                sin(elapsed * 37.0) * 0.7
                + sin(elapsed * 59.0) * 0.35
                + sin(elapsed * 83.0) * 0.2
            let bumpPulse = bumpStrength * (2.8 + sin(elapsed * 95.0) * 1.6)
            let vibY = micro + bumpPulse
            let vibRot = micro * 0.01 + bumpStrength * 0.028

            // Pozycja auta — na koniec wjeżdża w prawą krawędź i poza nią
            let baseX = w * 0.38
            let exitTravel = (w - baseX + 110) * exitProgress
            let carX = baseX + exitTravel
            let carY = roadY + CGFloat(vibY)
            let fade = max(0, 1 - Double(exitProgress - 0.82) / 0.18)

            // Particles przyspieszenia za autem
            drawAccelParticles(
                ctx,
                carX: carX,
                carY: carY,
                elapsed: elapsed,
                exitLinear: exitLinear,
                exitProgress: exitProgress,
                fade: fade,
                lime: lime
            )

            // Soft glow
            ctx.fill(
                Path(ellipseIn: CGRect(x: carX - 70, y: carY + 28, width: 140, height: 16)),
                with: .color(lime.opacity(0.08 * fade))
            )

            let wheelSpin =
                elapsed * (9.0 + Double(exitProgress) * 22.0)
                + Double(exitProgress) * 8.0

            ctx.drawLayer { layer in
                layer.opacity = fade
                layer.translateBy(x: carX, y: carY)
                layer.rotate(by: .radians(vibRot - Double(exitProgress) * 0.015))
                drawMinimalCar(layer, wheelAngle: wheelSpin, lime: lime)
            }
        }
    }

    // MARK: Pebbles

    private func drawPebbleCluster(_ ctx: GraphicsContext, at p: CGPoint, lime: Color) {
        let stones: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 5.5),
            (7, 2, 3.5),
            (-6, 1.5, 3.2),
            (3, -2, 2.4)
        ]
        for (ox, oy, r) in stones {
            let rect = CGRect(x: p.x + ox - r / 2, y: p.y + oy - r / 2, width: r, height: r * 0.75)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.28)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(lime.opacity(0.35)), lineWidth: 0.8)
        }
    }

    // MARK: Acceleration particles

    private func drawAccelParticles(
        _ ctx: GraphicsContext,
        carX: CGFloat,
        carY: CGFloat,
        elapsed: Double,
        exitLinear: CGFloat,
        exitProgress: CGFloat,
        fade: Double,
        lime: Color
    ) {
        let boost = max(0.15, Double(exitLinear))
        let count = 10 + Int(exitProgress * 18)

        // Speed streaks
        for i in 0..<count {
            let seed = Double(i) * 0.137 + elapsed * (1.8 + Double(exitProgress) * 4)
            let phase = seed.truncatingRemainder(dividingBy: 1)
            let spread = CGFloat((i % 5) - 2) * 7
            let lx = carX - 55 - CGFloat(phase) * (55 + exitProgress * 90)
            let ly = carY + spread - 4
            let len = 18 + exitProgress * 42 + CGFloat(i % 3) * 6
            let alpha = (0.12 + (1 - phase) * 0.55) * boost * fade
            let line = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .path(in: CGRect(x: lx - len, y: ly, width: len, height: 2 + exitProgress * 1.2))
            ctx.fill(line, with: .color(lime.opacity(alpha)))
        }

        // Spark dots
        for i in 0..<12 {
            let seed = Double(i) * 0.29 + elapsed * (2.4 + Double(exitProgress) * 5)
            let phase = seed.truncatingRemainder(dividingBy: 1)
            let px = carX - 48 - CGFloat(phase) * (40 + exitProgress * 70)
            let py = carY + CGFloat(sin(seed * 6.2)) * (12 + exitProgress * 10)
            let r: CGFloat = 1.4 + exitProgress * 1.8 * CGFloat(1 - phase)
            let a = (1 - phase) * boost * 0.85 * fade
            ctx.fill(
                Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                with: .color(lime.opacity(a))
            )
        }

        // Exhaust puff burst near rear during exit
        if exitProgress > 0.08 {
            for i in 0..<5 {
                let seed = Double(i) * 0.41 + elapsed * 3.1
                let phase = seed.truncatingRemainder(dividingBy: 1)
                let px = carX - 72 - CGFloat(phase) * 36 * exitProgress
                let py = carY + 6 - CGFloat(phase) * 14
                let s = 4 + CGFloat(phase) * 14 * exitProgress
                ctx.fill(
                    Path(ellipseIn: CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s * 0.85)),
                    with: .color(lime.opacity((1 - phase) * 0.25 * Double(exitProgress) * fade))
                )
            }
        }
    }

    // MARK: Car

    private func drawMinimalCar(_ ctx: GraphicsContext, wheelAngle: Double, lime: Color) {
        let cabin = RoundedRectangle(cornerRadius: 14, style: .continuous)
            .path(in: CGRect(x: -36, y: -34, width: 78, height: 34))
        ctx.fill(cabin, with: .color(lime.opacity(0.92)))

        let body = RoundedRectangle(cornerRadius: 18, style: .continuous)
            .path(in: CGRect(x: -68, y: -8, width: 136, height: 40))
        ctx.fill(body, with: .color(lime))

        let win = RoundedRectangle(cornerRadius: 8, style: .continuous)
            .path(in: CGRect(x: -18, y: -28, width: 52, height: 20))
        ctx.fill(win, with: .color(Color.black.opacity(0.55)))

        ctx.fill(Path(ellipseIn: CGRect(x: 58, y: 2, width: 10, height: 10)), with: .color(lime.opacity(0.95)))
        ctx.fill(Path(ellipseIn: CGRect(x: 56, y: 0, width: 14, height: 14)), with: .color(lime.opacity(0.25)))

        drawWheel(ctx, at: CGPoint(x: -40, y: 30), angle: wheelAngle, lime: lime)
        drawWheel(ctx, at: CGPoint(x: 40, y: 30), angle: wheelAngle, lime: lime)
    }

    private func drawWheel(_ ctx: GraphicsContext, at p: CGPoint, angle: Double, lime: Color) {
        ctx.drawLayer { layer in
            layer.translateBy(x: p.x, y: p.y)
            layer.fill(Path(ellipseIn: CGRect(x: -15, y: -15, width: 30, height: 30)), with: .color(Color(white: 0.12)))
            layer.stroke(Path(ellipseIn: CGRect(x: -15, y: -15, width: 30, height: 30)), with: .color(lime.opacity(0.85)), lineWidth: 2.2)
            layer.rotate(by: .radians(angle))
            layer.stroke(Path(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12)), with: .color(lime.opacity(0.55)), lineWidth: 1.5)
            layer.fill(
                RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: -1, y: -10, width: 2, height: 8)),
                with: .color(lime.opacity(0.7))
            )
        }
    }
}
