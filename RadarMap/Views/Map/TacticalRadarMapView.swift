import SwiftUI
import MapKit

#if canImport(WatchKit)
import WatchKit
#endif

public struct TacticalRadarMapView: View {
    @EnvironmentObject var gameState: GameStateManager
    #if os(watchOS)
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    #endif
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: AppConstants.Location.fallbackCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: AppConstants.UI.RadarScale.mapSpanDelta(forRadarScaleMeters: AppConstants.UI.RadarScale.defaultScaleMeters),
                longitudeDelta: AppConstants.UI.RadarScale.mapSpanDelta(forRadarScaleMeters: AppConstants.UI.RadarScale.defaultScaleMeters)
            )
        )
    )
    @State private var showingSettingsSheet: Bool = false
    @State private var hasInitializedCamera: Bool = false
    @State private var isInteractiveMapCameraChanging: Bool = false
    @State private var crownIndex: Double = AppConstants.UI.RadarScale.crownIndex(for: AppConstants.UI.RadarScale.defaultScaleMeters)
    @State private var lastCameraCenterCoordinate: CLLocationCoordinate2D? = nil
    #if os(watchOS)
    @FocusState private var isFocused: Bool
    #endif
    
    // Hold gesture state for KIA / Revive
    @State private var isHoldingActionButton: Bool = false
    @State private var actionProgress: Double = 0.0
    @State private var holdTimer: Timer? = nil
    @State private var holdStartTime: Date? = nil
    @State private var actionCompletedForCurrentTouch: Bool = false
    
    // EKG scan speed — cached so the body division doesn't rerun at 20 Hz when BPM is unchanged.
    @State private var sweepDuration: Double = AppConstants.Health.referenceBpm / AppConstants.Health.defaultRestingHeartRate
    
    public init() {}
    
    private var meMember: SquadMember {
        gameState.localPlayerMember
    }
    
    private var otherSquadMembers: [SquadMember] {
        gameState.otherSquadMembers
    }
    
    private var radarThemeColor: Color {
        gameState.radarColorTheme.color
    }
    
    private var uiThemeColor: Color {
        if gameState.selectedMapStyle == .radar {
            return radarThemeColor
        } else {
            return .primary
        }
    }
    
    public var body: some View {
        ZStack {
            // Tactical Standard MapKit Layer
            // Conditionally mounted — unmounting in radar mode stops MapKit tile decoding,
            // annotation walking, and camera callbacks entirely (not just hidden at opacity 0).
            // The @State `position` is preserved in this view and re-applied on re-mount.
            if gameState.selectedMapStyle != .radar {
                MapReader { proxy in
                    Map(
                        position: $position,
                        interactionModes: {
                            #if os(watchOS)
                            return MapInteractionModes.pan
                            #else
                            return [.pan, .zoom]
                            #endif
                        }()
                    ) {
                        // Remote Teammate Annotations (Smooth 60 FPS Gliding & Rotation)
                        ForEach(otherSquadMembers, id: \.id) { member in
                            let smoothed = gameState.deadReckoningEngine.smoothedMember(for: member)
                            Annotation(
                                "",
                                coordinate: smoothed.coordinate,
                                anchor: .center
                            ) {
                                MemberAnnotationView(
                                    member: smoothed,
                                    isMe: false,
                                    radarColor: radarThemeColor
                                )
                            }
                        }
                        
                        // Tactical Indicators
                        ForEach(gameState.allTacticalIndicators) { indicator in
                            Annotation(
                                "",
                                coordinate: indicator.coordinate,
                                anchor: .center
                            ) {
                                TacticalIndicatorOverlayView(
                                    indicator: indicator,
                                    radarColor: radarThemeColor,
                                    onDelete: {
                                        gameState.removeTacticalIndicator(id: indicator.id)
                                    }
                                )
                            }
                        }
                        
                        // Local Player "Me" (Anchors smoothly to localPlayerMember coordinate)
                        Annotation(
                            "",
                            coordinate: meMember.coordinate,
                            anchor: .center
                        ) {
                            MemberAnnotationView(
                                member: meMember,
                                isMe: true,
                                radarColor: radarThemeColor
                            )
                        }
                    }
                    .mapStyle(gameState.selectedMapStyle.mapKitStyle)
                    .mapControls { }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        #if !os(watchOS)
                        let newDelta = context.region.span.latitudeDelta
                        let calculatedScale = AppConstants.UI.RadarScale.radarScaleMeters(forMapSpanDelta: newDelta)
                        if abs(gameState.radarScaleMeters - calculatedScale) > 0.5 {
                            gameState.radarScaleMeters = calculatedScale
                            crownIndex = AppConstants.UI.RadarScale.crownIndex(for: calculatedScale)
                        }
                        #endif
                        
                        let center = context.region.center
                        let dLat = (center.latitude - meMember.coordinate.latitude) * AppConstants.Location.metersPerDegreeLatitude
                        let dLon = (center.longitude - meMember.coordinate.longitude) * AppConstants.Location.metersPerDegreeLatitude * cos(center.latitude * AppConstants.Location.degreesToRadiansFactor)
                        let dist = hypot(dLat, dLon)
                        let minPanThreshold = max(15.0, gameState.radarScaleMeters * 0.25)
                        if dist > minPanThreshold {
                            gameState.currentMapCenter = center
                            lastCameraCenterCoordinate = center
                        }
                    }
                    .onTapGesture { screenPoint in
                        if gameState.pendingIndicatorPlacementType != nil,
                           let coordinate = proxy.convert(screenPoint, from: .local) {
                            gameState.placeTacticalIndicator(at: coordinate)
                        }
                        #if os(watchOS)
                        requestCrownFocus()
                        #endif
                    }
                    .edgesIgnoringSafeArea(.all)
                }
                .edgesIgnoringSafeArea(.all)
                .zIndex(0)
            }
            
            // OLED Power-Saving Radar View
            if gameState.selectedMapStyle == .radar {
                SimpleRadarMapView()
                    .edgesIgnoringSafeArea(.all)
                    .zIndex(1)
            }
            
            // Tactical HUD Overlays (Highest priority over map)
            VStack {
                // Top HUD (Upper left: Config, Center: Squad Leader 3-star button, Upper right: Clear for watchOS clock)
                HStack(alignment: .center) {
                    Button(action: {
                        showingSettingsSheet = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(uiThemeColor)
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded {
                                showingSettingsSheet = true
                            }
                    )
                    
                    Spacer()
                    
                    // Center Top: Squad Leader Button (3-star icon, identical 48x24 shape to bottom EKG indicator)
                    // Only shown for Pro owners
                    if gameState.subscriptionManager.hasUnlimitedSquadUnlock {
                        Button(action: {
                            gameState.openIndicatorMenu()
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.black.opacity(0.85))
                                
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10, weight: .black))
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundColor(uiThemeColor)
                                
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(uiThemeColor.opacity(0.75), lineWidth: 1.0)
                            }
                            .frame(width: 48, height: 24)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .frame(minWidth: 48, minHeight: 44)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            TapGesture()
                                .onEnded {
                                    gameState.openIndicatorMenu()
                                }
                        )
                    } else {
                        // Empty placeholder keeping layout alignment
                        Color.clear
                            .frame(width: 48, height: 44)
                    }
                    
                    Spacer()
                    
                    // Empty 44x44 placeholder to keep center button centered while keeping top right clear for watchOS clock
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, AppConstants.UI.HUD.horizontalPadding)
                .padding(.top, AppConstants.UI.HUD.topPadding)
                
                Spacer()
                
                // Bottom HUD: Center/Zoom (bottom left), Ruler or KIA (bottom center), Map Style Switch (bottom right)
                HStack(alignment: .center) {
                    // Bottom left: Map centering & default zoom (all views)
                    Button(action: {
                        centerMapToUser()
                    }) {
                        Image(systemName: gameState.currentMapCenter == nil ? "location.fill" : "location")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(uiThemeColor)
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded {
                                centerMapToUser()
                            }
                    )
                    
                    Spacer()
                    
                    // Bottom center: Fixed slot for both views (KIA on Radar, Ruler on MapKit)
                    Group {
                        if gameState.selectedMapStyle == .radar {
                            let themeColor = uiThemeColor
                            let buttonWidth: CGFloat = 48
                            let buttonHeight: CGFloat = 24
                            #if os(watchOS)
                            let scanInterval = isLuminanceReduced ? 1.0 : AppConstants.Timing.DisplayRefresh.radarUIIntervalSeconds
                            #else
                            let scanInterval = AppConstants.Timing.DisplayRefresh.radarUIIntervalSeconds
                            #endif
                            
                            TimelineView(.periodic(from: .now, by: scanInterval)) { timeline in
                                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                                let progress = (elapsed.truncatingRemainder(dividingBy: sweepDuration)) / sweepDuration
                                let ekgSize = CGSize(width: 32, height: 14)
                                
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.black.opacity(0.85))
                                    
                                    // Left-to-right progress fill on hold
                                    if actionProgress > 0 {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(themeColor.opacity(0.55))
                                            .frame(width: max(0, buttonWidth * CGFloat(actionProgress)))
                                    }
                                    
                                    // Center EKG graphic with tracking scanning dot
                                    ZStack {
                                        // Heartbeat pulse wave (ECG waveform or flatline when dead)
                                        ECGWaveShape(isFlatline: gameState.isDead)
                                            .stroke(
                                                themeColor.opacity(gameState.isDead ? 0.7 : 0.45),
                                                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
                                            )
                                        
                                        // Scanning dot riding along the EKG / flatline line
                                        let dotPos = ECGWaveShape.point(at: CGFloat(progress), in: ekgSize, isFlatline: gameState.isDead)
                                        
                                        // Subtle glow halo
                                        Circle()
                                            .fill(themeColor.opacity(0.35))
                                            .frame(width: 5.5, height: 5.5)
                                            .position(dotPos)
                                        
                                        // Bright center core dot
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 2.2, height: 2.2)
                                            .position(dotPos)
                                    }
                                    .frame(width: ekgSize.width, height: ekgSize.height)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    
                                    // Tactical outer border
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(
                                            themeColor.opacity(isHoldingActionButton ? 1.0 : 0.75),
                                            lineWidth: isHoldingActionButton ? 1.5 : 1.0
                                        )
                                }
                                .frame(width: buttonWidth, height: buttonHeight)
                            }
                            .frame(minWidth: 48, minHeight: 44)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        startActionHold()
                                    }
                                    .onEnded { _ in
                                        cancelActionHold()
                                    }
                            )
                        } else {
                            // Tactical Scale Ruler for MapKit views (Fixed slot matching KIA button)
                            VStack(spacing: 2) {
                                // Ruler notches
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(uiThemeColor.opacity(0.9))
                                        .frame(width: 1.5, height: 5)
                                    
                                    Rectangle()
                                        .fill(uiThemeColor.opacity(0.6))
                                        .frame(width: 16, height: 1)
                                    
                                    Rectangle()
                                        .fill(uiThemeColor.opacity(0.9))
                                        .frame(width: 1, height: 3.5)
                                    
                                    Rectangle()
                                        .fill(uiThemeColor.opacity(0.6))
                                        .frame(width: 16, height: 1)
                                    
                                    Rectangle()
                                        .fill(uiThemeColor.opacity(0.9))
                                        .frame(width: 1.5, height: 5)
                                }
                                
                                Text(gameState.currentScaleText)
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(uiThemeColor.opacity(0.9))
                            }
                            .frame(width: 48, height: 24)
                            .background(Color.black.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(uiThemeColor.opacity(0.35), lineWidth: 1)
                            )
                            .cornerRadius(5)
                            .frame(minWidth: 48, minHeight: 44)
                        }
                    }
                    .frame(minWidth: 48, minHeight: 44)
                    
                    Spacer()
                    
                    // Bottom right: Map style cycling
                    Button(action: {
                        toggleNextMapStyle()
                    }) {
                        Image(systemName: gameState.selectedMapStyle.iconName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(uiThemeColor)
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded {
                                toggleNextMapStyle()
                            }
                    )
                }
                .padding(.horizontal, AppConstants.UI.HUD.horizontalPadding)
                .padding(.bottom, AppConstants.UI.HUD.bottomPadding)
            }
            .edgesIgnoringSafeArea(.all)
            .zIndex(10)
        }
        #if os(watchOS)
        .focusable()
        .focused($isFocused)
        .defaultFocus($isFocused, true)
        .digitalCrownRotation(
            $crownIndex,
            from: 0.0,
            through: Double(AppConstants.UI.RadarScale.discreteScales.count - 1),
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        #endif
        .navigationTitle("Radar")
        #if os(watchOS) || os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                SettingsView()
                    .environmentObject(gameState)
            }
        }
        .sheet(isPresented: $gameState.showIndicatorMenuSheet) {
            TacticalIndicatorMenuView()
                .environmentObject(gameState)
        }
        .sheet(isPresented: $gameState.showPaywallSheet) {
            NavigationStack {
                PaywallView()
                    .environmentObject(gameState)
            }
        }
        #if os(watchOS)
        .onChange(of: isFocused) { _, newValue in
            if !newValue && !showingSettingsSheet && !gameState.showIndicatorMenuSheet && !gameState.showPaywallSheet {
                requestCrownFocus()
            }
        }
        .onChange(of: gameState.selectedMapStyle) { _, _ in
            requestCrownFocus()
        }
        .onChange(of: showingSettingsSheet) { _, isShowing in
            if !isShowing {
                requestCrownFocus()
            }
        }
        .onChange(of: gameState.showIndicatorMenuSheet) { _, isShowing in
            if !isShowing {
                requestCrownFocus()
            }
        }
        .onChange(of: gameState.showPaywallSheet) { _, isShowing in
            if !isShowing {
                requestCrownFocus()
            }
        }
        #endif
        .onChange(of: crownIndex) { _, newIndex in
            let newScale = AppConstants.UI.RadarScale.scale(forCrownIndex: newIndex)
            if abs(gameState.radarScaleMeters - newScale) > 0.5 {
                gameState.radarScaleMeters = newScale
                if gameState.selectedMapStyle != .radar {
                    let latDelta = gameState.currentMapSpanDelta
                    let targetCenter = gameState.currentMapCenter ?? meMember.coordinate
                    lastCameraCenterCoordinate = targetCenter
                    position = .region(
                        MKCoordinateRegion(
                            center: targetCenter,
                            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
                        )
                    )
                }
            }
        }
        .onChange(of: gameState.radarCenterTrigger) { _, _ in
            let latDelta = gameState.currentMapSpanDelta
            crownIndex = AppConstants.UI.RadarScale.crownIndex(for: gameState.radarScaleMeters)
            lastCameraCenterCoordinate = meMember.coordinate
            withAnimation(.easeInOut(duration: 0.25)) {
                position = .region(
                    MKCoordinateRegion(
                        center: meMember.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
                    )
                )
            }
        }
        .onChange(of: gameState.currentMapCenter) { _, newCenter in
            if newCenter == nil {
                let latDelta = gameState.currentMapSpanDelta
                lastCameraCenterCoordinate = meMember.coordinate
                withAnimation(.easeInOut(duration: 0.25)) {
                    position = .region(
                        MKCoordinateRegion(
                            center: meMember.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
                        )
                    )
                }
            } else {
                lastCameraCenterCoordinate = newCenter
            }
        }
        .onChange(of: meMember.coordinate.latitude) { _, _ in
            handlePlayerCoordinateChange()
        }
        .onChange(of: meMember.coordinate.longitude) { _, _ in
            handlePlayerCoordinateChange()
        }
        .onAppear {
            crownIndex = AppConstants.UI.RadarScale.crownIndex(for: gameState.radarScaleMeters)
            let latDelta = gameState.currentMapSpanDelta
            let targetCenter = gameState.currentMapCenter ?? meMember.coordinate
            lastCameraCenterCoordinate = targetCenter
            position = .region(
                MKCoordinateRegion(
                    center: targetCenter,
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
                )
            )
            #if os(watchOS)
            requestCrownFocus()
            #endif
            gameState.locationHeadingManager.requestPermissions()
            gameState.locationHeadingManager.startUpdates()
            // Seed sweepDuration from the current heart rate on appear.
            let bpm = gameState.healthKitManager.currentHeartRate > 0 ? gameState.healthKitManager.currentHeartRate : AppConstants.Health.defaultRestingHeartRate
            sweepDuration = AppConstants.Health.referenceBpm / bpm
        }
        .onChange(of: gameState.healthKitManager.currentHeartRate) { _, newRate in
            // Recompute EKG sweep period when BPM changes — not on every 20 Hz render tick.
            let bpm = newRate > 0 ? newRate : AppConstants.Health.defaultRestingHeartRate
            sweepDuration = AppConstants.Health.referenceBpm / bpm
        }
        .onDisappear {
            cancelActionHold()
        }
    }
    
    private func handlePlayerCoordinateChange() {
        guard gameState.currentMapCenter == nil && gameState.selectedMapStyle != .radar else { return }
        let currentCoord = meMember.coordinate
        lastCameraCenterCoordinate = currentCoord
        let latDelta = gameState.currentMapSpanDelta
        position = .region(
            MKCoordinateRegion(
                center: currentCoord,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
            )
        )
    }
    
    #if os(watchOS)
    private func requestCrownFocus() {
        isFocused = true
        DispatchQueue.main.async {
            isFocused = true
        }
    }
    #endif
    
    // MARK: - Hold-to-Act (KIA / Revive) Gesture Handling
    
    private func startActionHold() {
        guard !isHoldingActionButton, !actionCompletedForCurrentTouch else { return }
        isHoldingActionButton = true
        holdStartTime = Date()
        actionProgress = 0.0
        
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: AppConstants.UI.Gestures.holdTimerTickIntervalSeconds, repeats: true) { _ in
            guard let startTime = holdStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            let duration: TimeInterval = AppConstants.UI.Gestures.actionHoldDurationSeconds
            
            let progress = min(1.0, elapsed / duration)
            withAnimation(.linear(duration: AppConstants.UI.Gestures.holdTimerTickIntervalSeconds)) {
                actionProgress = progress
            }
            
            if progress >= 1.0 {
                triggerAction()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }
    
    private func cancelActionHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        actionCompletedForCurrentTouch = false
        withAnimation(.easeOut(duration: 0.2)) {
            isHoldingActionButton = false
            actionProgress = 0.0
        }
        #if os(watchOS)
        requestCrownFocus()
        #endif
    }
    
    private func triggerAction() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        isHoldingActionButton = false
        actionCompletedForCurrentTouch = true
        actionProgress = 0.0
        
        withAnimation(.easeInOut(duration: AppConstants.UI.Gestures.actionAnimationDurationSeconds)) {
            gameState.setDead(!gameState.isDead)
        }
        #if os(watchOS)
        requestCrownFocus()
        #endif
    }
    
    private func centerMapToUser() {
        gameState.resetMapToDefaultCenterAndZoom()
        #if os(watchOS)
        requestCrownFocus()
        #endif
    }
    
    private func toggleNextMapStyle() {
        switch gameState.selectedMapStyle {
        case .standard:
            gameState.selectedMapStyle = .radar
        case .radar:
            gameState.selectedMapStyle = .standard
            let latDelta = gameState.currentMapSpanDelta
            let targetCenter = gameState.currentMapCenter ?? gameState.localPlayerMember.coordinate
            position = .region(
                MKCoordinateRegion(
                    center: targetCenter,
                    span: MKCoordinateSpan(
                        latitudeDelta: latDelta,
                        longitudeDelta: latDelta
                    )
                )
            )
        }
        #if os(watchOS)
        crownIndex = AppConstants.UI.RadarScale.crownIndex(for: gameState.radarScaleMeters)
        requestCrownFocus()
        #endif
    }
}
