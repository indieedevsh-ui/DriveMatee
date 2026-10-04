import SwiftUI
import MapKit
import QuartzCore

/// Jednolita limonkowa linia trasy z animowanym „rysowaniem” (progress 0…1).
final class LimeRouteRenderer: MKPolylineRenderer {
    var routeColor: UIColor = DriveMatePalette.limeRouteUI
    private var _drawProgress: CGFloat = 1
    private var cachedLengths: [CGFloat] = []
    private var cachedTotal: CGFloat = 0
    private var cachedPointCount: Int = 0

    var drawProgress: CGFloat {
        get { _drawProgress }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard abs(clamped - _drawProgress) > 0.001 else { return }
            _drawProgress = clamped
            // Pełny invalidation — częściowy setNeedsDisplay bywa pomijany przy szybkich update’ach kamery.
            setNeedsDisplay()
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let polyline = overlay as? MKPolyline, polyline.pointCount > 1 else {
            super.draw(mapRect, zoomScale: zoomScale, in: context)
            return
        }

        rebuildLengthCacheIfNeeded(polyline)

        let target = cachedTotal * _drawProgress
        guard target > 1, cachedTotal > 0 else { return }

        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))

        let path = CGMutablePath()
        var traveled: CGFloat = 0
        path.move(to: point(for: MKMapPoint(coords[0])))

        for i in 1..<coords.count {
            let seg = cachedLengths[i - 1]
            let nextTravel = traveled + seg
            if nextTravel <= target + 0.01 {
                path.addLine(to: point(for: MKMapPoint(coords[i])))
                traveled = nextTravel
            } else {
                let remain = max(0, target - traveled)
                let t = seg > 0 ? remain / seg : 0
                let a = MKMapPoint(coords[i - 1])
                let b = MKMapPoint(coords[i])
                let mid = MKMapPoint(
                    x: a.x + (b.x - a.x) * Double(t),
                    y: a.y + (b.y - a.y) * Double(t)
                )
                path.addLine(to: point(for: mid))
                break
            }
        }

        context.saveGState()
        context.setStrokeColor(routeColor.cgColor)
        // Stała grubość na ekranie
        let width = max(lineWidth, 9) / zoomScale
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShouldAntialias(true)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private func rebuildLengthCacheIfNeeded(_ polyline: MKPolyline) {
        guard polyline.pointCount != cachedPointCount || cachedLengths.isEmpty else { return }
        cachedPointCount = polyline.pointCount
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        cachedLengths.removeAll(keepingCapacity: true)
        cachedTotal = 0
        for i in 1..<coords.count {
            let a = MKMapPoint(coords[i - 1])
            let b = MKMapPoint(coords[i])
            let d = CGFloat(hypot(b.x - a.x, b.y - a.y))
            cachedLengths.append(d)
            cachedTotal += d
        }
    }
}

/// Biały trójkąt kierunkowy (jak chevron z linii).
enum RouteArrowImage {
    static func whiteTriangle(size: CGFloat = 28) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let c = ctx.cgContext
            let tip = CGPoint(x: size * 0.5, y: size * 0.08)
            let left = CGPoint(x: size * 0.12, y: size * 0.88)
            let right = CGPoint(x: size * 0.88, y: size * 0.88)
            let path = CGMutablePath()
            path.move(to: tip)
            path.addLine(to: left)
            path.addLine(to: right)
            path.closeSubpath()
            c.setFillColor(UIColor.white.cgColor)
            c.addPath(path)
            c.fillPath()
            c.setStrokeColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            c.setLineWidth(1)
            c.addPath(path)
            c.strokePath()
        }
    }
}

final class TurnArrowAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let heading: CLLocationDirection
    let isLeft: Bool
    let isRight: Bool
    let title: String?

    init(maneuver: TurnManeuver) {
        coordinate = maneuver.coordinate
        heading = maneuver.heading
        isLeft = maneuver.isLeft
        isRight = maneuver.isRight
        title = maneuver.instruction
        super.init()
    }
}

struct MapDriveView: View {
    @ObservedObject var location: LocationSpeedService
    @ObservedObject var mapState: NavigationMapState
    var isDark: Bool
    /// Gdy panel muzyki jest widoczny — pastylka Legal unosi się wyżej.
    var musicBarVisible: Bool = false
    /// Wyrównanie do chrome (sidebar) — lekko odklejone od lewej treści.
    var leadingChrome: CGFloat = 168
    var onUserInteraction: (() -> Void)? = nil

    @State private var showLegal = false

    /// Ten sam dolny offset co przycisk „Zakończ trasę”.
    private var legalBottomPadding: CGFloat { musicBarVisible ? 118 : 22 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AppleMapsView(
                userCoordinate: location.coordinate,
                destinationCoordinate: mapState.destinationCoordinate,
                destinationTitle: mapState.destinationTitle,
                routePolyline: mapState.route?.polyline,
                alternatePolylines: mapState.alternateRoutes.map(\.polyline),
                turnManeuvers: mapState.turnManeuvers,
                cameraFocus: mapState.cameraFocus,
                isFollowingUser: mapState.isFollowingUser,
                isNavigating: mapState.isNavigating,
                isAnimatingRouteReveal: mapState.isAnimatingRouteReveal,
                routeDrawProgress: mapState.routeDrawProgress,
                routeRevealCameraCoordinate: mapState.routeRevealCameraCoordinate,
                destinationFlagVisible: mapState.destinationFlagVisible,
                destinationFlagBounceToken: mapState.destinationFlagBounceToken,
                isDark: isDark,
                showsTraffic: mapState.isNavigating,
                onUserPan: { mapState.userPannedMap() },
                onUserInteraction: onUserInteraction
            )
            .ignoresSafeArea()

            Button {
                onUserInteraction?()
                showLegal = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "apple.logo").font(.system(size: 11, weight: .semibold))
                    Text("Maps").font(.system(size: 11, weight: .semibold))
                    Text("·")
                    Text("Legal").font(.system(size: 11, weight: .medium)).underline()
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassCapsule(.clear)
            }
            .buttonStyle(.plain)
            .padding(.leading, leadingChrome + 10)
            .padding(.bottom, legalBottomPadding)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: musicBarVisible)
        }
        .onAppear {
            location.requestAccessAndStart()
            // Animacja rysowania linii — dopiero gdy mapa jest na ekranie.
            mapState.startRouteRevealWhenMapReady()
        }
        .onChange(of: mapState.routeRevealRequestID) { _, _ in
            mapState.startRouteRevealWhenMapReady()
        }
        .sheet(isPresented: $showLegal) {
            NavigationStack {
                List {
                    Section("Źródło mapy") {
                        Text("Dane mapy są dostarczane przez Apple Maps (MapKit).")
                    }
                    Section("Prawa autorskie") {
                        Link("Apple Maps Legal", destination: URL(string: "https://www.apple.com/legal/internet-services/maps/")!)
                    }
                }
                .navigationTitle("Legal")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Gotowe") { showLegal = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

struct AppleMapsView: UIViewRepresentable {
    var userCoordinate: CLLocationCoordinate2D?
    var destinationCoordinate: CLLocationCoordinate2D?
    var destinationTitle: String?
    var routePolyline: MKPolyline?
    var alternatePolylines: [MKPolyline]
    var turnManeuvers: [TurnManeuver]
    var cameraFocus: NavigationMapState.CameraFocus
    var isFollowingUser: Bool
    var isNavigating: Bool
    var isAnimatingRouteReveal: Bool
    var routeDrawProgress: CGFloat
    var routeRevealCameraCoordinate: CLLocationCoordinate2D?
    var destinationFlagVisible: Bool
    var destinationFlagBounceToken: Int
    var isDark: Bool
    var showsTraffic: Bool
    var onUserPan: () -> Void
    var onUserInteraction: (() -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = true
        map.pointOfInterestFilter = .includingAll
        map.layoutMargins = UIEdgeInsets(top: 0, left: 160, bottom: 110, right: 48)
        map.overrideUserInterfaceStyle = isDark ? .dark : .light
        map.mapType = .standard
        // Atrybucja tylko w pastylce liquid glass — ukryj natywne logo Apple Maps.
        Self.hideNativeAppleMapsChrome(in: map)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)

        let touch = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTouch(_:)))
        touch.delegate = context.coordinator
        touch.cancelsTouchesInView = false
        map.addGestureRecognizer(touch)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.overrideUserInterfaceStyle = isDark ? .dark : .light
        map.showsTraffic = showsTraffic
        Self.hideNativeAppleMapsChrome(in: map)
        context.coordinator.onUserPan = onUserPan
        context.coordinator.onUserInteraction = onUserInteraction
        context.coordinator.isFollowingUser = isFollowingUser
        context.coordinator.isNavigating = isNavigating
        context.coordinator.isAnimatingRouteReveal = isAnimatingRouteReveal
        context.coordinator.sync(
            map: map,
            userCoordinate: userCoordinate,
            destinationCoordinate: destinationCoordinate,
            destinationTitle: destinationTitle,
            routePolyline: routePolyline,
            alternatePolylines: alternatePolylines,
            turnManeuvers: turnManeuvers,
            cameraFocus: cameraFocus,
            routeDrawProgress: routeDrawProgress,
            routeRevealCameraCoordinate: routeRevealCameraCoordinate,
            destinationFlagVisible: destinationFlagVisible,
            destinationFlagBounceToken: destinationFlagBounceToken
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Ukrywa systemowe logo / etykietę Apple Maps — zostaje tylko nasza pastylka Legal.
    static func hideNativeAppleMapsChrome(in map: MKMapView) {
        func hide(_ view: UIView) {
            let name = NSStringFromClass(type(of: view))
            if name.contains("Attribution")
                || name.contains("AppleLogo")
                || name.contains("LogoImage")
                || name.contains("MKOverlayLabel") {
                view.isHidden = true
                view.alpha = 0
            }
            view.subviews.forEach(hide)
        }
        map.subviews.forEach(hide)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onUserPan: (() -> Void)?
        var onUserInteraction: (() -> Void)?
        var isFollowingUser = true
        var isNavigating = false
        var isAnimatingRouteReveal = false

        private var destinationAnnotation: MKPointAnnotation?
        private var turnAnnotations: [TurnArrowAnnotation] = []
        private var lastRouteHash = 0
        private var lastFocus: NavigationMapState.CameraFocus?
        private var lastFollowCoord: CLLocationCoordinate2D?
        private weak var primaryRouteRenderer: LimeRouteRenderer?
        private var pendingDrawProgress: CGFloat = 0
        private var lastBounceToken: Int = -1
        private weak var flagView: MKMarkerAnnotationView?

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            onUserInteraction?()
            guard isNavigating, !isAnimatingRouteReveal else { return }
            guard gesture.state == .began || gesture.state == .changed else { return }
            onUserPan?()
        }

        @objc func handleTouch(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onUserInteraction?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func sync(
            map: MKMapView,
            userCoordinate: CLLocationCoordinate2D?,
            destinationCoordinate: CLLocationCoordinate2D?,
            destinationTitle: String?,
            routePolyline: MKPolyline?,
            alternatePolylines: [MKPolyline],
            turnManeuvers: [TurnManeuver],
            cameraFocus: NavigationMapState.CameraFocus,
            routeDrawProgress: CGFloat,
            routeRevealCameraCoordinate: CLLocationCoordinate2D?,
            destinationFlagVisible: Bool,
            destinationFlagBounceToken: Int
        ) {
            pendingDrawProgress = routeDrawProgress

            let routeHash = Self.contentHash(
                polyline: routePolyline,
                destination: destinationCoordinate,
                maneuverCount: turnManeuvers.count
            )

            if routeHash != lastRouteHash {
                lastRouteHash = routeHash
                lastFocus = nil
                primaryRouteRenderer = nil
                map.removeOverlays(map.overlays)
                if let routePolyline {
                    map.addOverlay(routePolyline, level: .aboveRoads)
                    for alt in alternatePolylines {
                        map.addOverlay(alt, level: .aboveRoads)
                    }
                }

                map.removeAnnotations(turnAnnotations)
                if !isAnimatingRouteReveal {
                    turnAnnotations = turnManeuvers.map(TurnArrowAnnotation.init)
                    map.addAnnotations(turnAnnotations)
                } else {
                    turnAnnotations = []
                }
            }

            if let renderer = primaryRouteRenderer {
                renderer.drawProgress = routeDrawProgress
            } else if routePolyline != nil, isAnimatingRouteReveal {
                // Renderer jeszcze nie powstał — wymuś odświeżenie overlayi przy następnym cyklu.
                map.setNeedsDisplay()
            }

            if !isAnimatingRouteReveal, turnAnnotations.isEmpty, !turnManeuvers.isEmpty {
                turnAnnotations = turnManeuvers.map(TurnArrowAnnotation.init)
                map.addAnnotations(turnAnnotations)
            }

            // Flaga celu dopiero na końcu rysowania
            if destinationFlagVisible, let dest = destinationCoordinate {
                if let existing = destinationAnnotation {
                    existing.coordinate = dest
                    existing.title = destinationTitle
                } else {
                    let pin = MKPointAnnotation()
                    pin.coordinate = dest
                    pin.title = destinationTitle ?? "Cel"
                    map.addAnnotation(pin)
                    destinationAnnotation = pin
                }
            } else if let existing = destinationAnnotation {
                map.removeAnnotation(existing)
                destinationAnnotation = nil
                flagView = nil
            }

            if destinationFlagVisible,
               destinationFlagBounceToken != lastBounceToken,
               let flagView {
                lastBounceToken = destinationFlagBounceToken
                Self.bounceFlag(flagView)
            }

            // Intro: kamera podąża za czubkiem rysowanej linii
            if isAnimatingRouteReveal {
                if let tip = routeRevealCameraCoordinate {
                    let heading: CLLocationDirection
                    if let poly = routePolyline {
                        heading = RouteGeometry.heading(along: poly, progress: routeDrawProgress)
                    } else {
                        heading = map.camera.heading
                    }
                    let camera = MKMapCamera(
                        lookingAtCenter: tip,
                        fromDistance: 780,
                        pitch: 48,
                        heading: heading
                    )
                    CATransaction.begin()
                    CATransaction.setDisableActions(false)
                    CATransaction.setAnimationDuration(0.08)
                    CATransaction.setAnimationTimingFunction(
                        CAMediaTimingFunction(name: .linear)
                    )
                    map.camera = camera
                    CATransaction.commit()
                }
                return
            }

            if isNavigating, isFollowingUser, let userCoordinate {
                let movedEnough: Bool = {
                    guard let last = lastFollowCoord else { return true }
                    let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    let b = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
                    return a.distance(from: b) > 6
                }()
                let shouldSnap = cameraFocus == .follow || cameraFocus == .user || lastFocus != .follow
                if movedEnough || shouldSnap {
                    lastFollowCoord = userCoordinate
                    lastFocus = .follow
                    UIView.animate(
                        withDuration: 0.55,
                        delay: 0,
                        options: [.curveEaseInOut, .allowUserInteraction]
                    ) {
                        map.camera = MKMapCamera(
                            lookingAtCenter: userCoordinate,
                            fromDistance: 850,
                            pitch: 0,
                            heading: 0
                        )
                    }
                }
                return
            }

            if cameraFocus != lastFocus {
                lastFocus = cameraFocus
                switch cameraFocus {
                case .user, .follow:
                    if let userCoordinate {
                        UIView.animate(withDuration: 0.55, delay: 0, options: [.curveEaseInOut]) {
                            map.camera = MKMapCamera(
                                lookingAtCenter: userCoordinate,
                                fromDistance: 1000,
                                pitch: 0,
                                heading: 0
                            )
                        }
                    }
                case .destination:
                    if let dest = destinationCoordinate {
                        map.setCamera(
                            MKMapCamera(lookingAtCenter: dest, fromDistance: 700, pitch: 35, heading: 0),
                            animated: true
                        )
                    }
                case .route:
                    if let routePolyline {
                        map.setVisibleMapRect(
                            routePolyline.boundingMapRect,
                            edgePadding: UIEdgeInsets(top: 70, left: 190, bottom: 150, right: 56),
                            animated: true
                        )
                    }
                }
            }
        }

        private static func bounceFlag(_ view: MKAnnotationView) {
            view.layer.removeAllAnimations()
            view.transform = .identity
            UIView.animateKeyframes(withDuration: 0.72, delay: 0, options: [.calculationModeCubic]) {
                UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.22) {
                    view.transform = CGAffineTransform(translationX: 0, y: -16).scaledBy(x: 1.08, y: 1.08)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.22, relativeDuration: 0.2) {
                    view.transform = CGAffineTransform(translationX: 0, y: 0).scaledBy(x: 0.96, y: 0.96)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.42, relativeDuration: 0.18) {
                    view.transform = CGAffineTransform(translationX: 0, y: -9).scaledBy(x: 1.04, y: 1.04)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.2) {
                    view.transform = .identity
                }
            }
        }

        private static func contentHash(
            polyline: MKPolyline?,
            destination: CLLocationCoordinate2D?,
            maneuverCount: Int
        ) -> Int {
            var h = maneuverCount &<< 10
            if let destination {
                h ^= Int(destination.latitude * 100_000)
                h ^= Int(destination.longitude * 100_000)
            }
            if let polyline, polyline.pointCount > 0 {
                h ^= polyline.pointCount
                let pts = polyline.points()
                h ^= Int(pts[0].x / 50)
                h ^= Int(pts[polyline.pointCount - 1].y / 50)
                h ^= Int(polyline.boundingMapRect.size.width / 25)
            }
            return h
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let isPrimary = mapView.overlays.first(where: { $0 is MKPolyline }) === overlay
            if isPrimary {
                let renderer = LimeRouteRenderer(polyline: polyline)
                renderer.lineWidth = 11
                renderer.routeColor = DriveMatePalette.limeRouteUI
                // Start od aktualnego postępu (0 na początku animacji).
                renderer.drawProgress = pendingDrawProgress
                primaryRouteRenderer = renderer
                return renderer
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = DriveMatePalette.limeRouteUI.withAlphaComponent(0.4)
            renderer.lineWidth = 4
            renderer.lineDashPattern = [6, 8]
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let turn = annotation as? TurnArrowAnnotation {
                let id = "turnArrowTriangle"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.image = RouteArrowImage.whiteTriangle(size: 30)
                view.centerOffset = .zero
                view.canShowCallout = true
                view.transform = CGAffineTransform(rotationAngle: CGFloat(turn.heading * .pi / 180))
                return view
            }

            let id = "driveMateDestination"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = DriveMatePalette.limeRouteUI
            view.glyphImage = UIImage(systemName: "flag.fill")
            view.canShowCallout = true
            flagView = view
            return view
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views {
                guard view === flagView || (view.annotation as? MKPointAnnotation) === destinationAnnotation else {
                    continue
                }
                // Podskok zaraz po pojawieniu się flagi
                Self.bounceFlag(view)
            }
        }
    }
}
