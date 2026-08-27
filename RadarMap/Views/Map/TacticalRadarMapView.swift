import SwiftUI
import MapKit

#if canImport(WatchKit)
import WatchKit
#endif

public struct TacticalRadarMapView: View {
    @EnvironmentObject var gameState: GameStateManager
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var showingSettingsSheet: Bool = false
    @State private var hasInitializedCamera: Bool = false
    @State private var isProgrammaticCameraChange: Bool = false
    
    // Hold gesture state for KIA / Revive
    @State private var isHoldingActionButton: Bool = false
    @State private var actionProgress: Double = 0.0
    @State private var holdTimer: Timer? = nil
    @State private var holdStartTime: Date? = nil
    @State private var actionCompletedForCurrentTouch: Bool = false
    
    public init() {}
    
    private var otherSquadMembers: [SquadMember] {
        guard let room = gameState.firebaseManager.activeRoom else { return [] }
        return room.members.values.filter { $0.id != gameState.myMemberId }
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
            // Tactical Standard MapKit Layer (Kept mounted to preserve camera cache, zoom & center)
            let meMember = gameState.localPlayerMember
            MapReader { proxy in
                Map(position: $position) {
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
                    
                    // User Location "Me" (Explicit center anchor to prevent swaying / bobbing)
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
                .mapControls {
                    MapCompass()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    guard gameState.selectedMapStyle != .radar else { return }
                    guard !isProgrammaticCameraChange else {
                        isProgrammaticCameraChange = false
                        return
                    }
                    gameState.currentMapSpanDelta = context.region.span.latitudeDelta
                    
                    let centerLoc = CLLocation(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                    let userLoc = gameState.locationHeadingManager.userLocation ?? CLLocation(latitude: AppConstants.Location.fallbackLatitude, longitude: AppConstants.Location.fallbackLongitude)
                    if centerLoc.distance(from: userLoc) > 8.0 {
                        gameState.currentMapCenter = context.region.center
                    } else {
                        gameState.currentMapCenter = nil
                    }
                }
                .onTapGesture { screenPoint in
                    if gameState.pendingIndicatorPlacementType != nil,
                       let coordinate = proxy.convert(screenPoint, from: .local) {
                        gameState.placeTacticalIndicator(at: coordinate)
                    }
                }
                .edgesIgnoringSafeArea(.all)
            }
            .opacity(gameState.selectedMapStyle != .radar ? 1.0 : 0.0)
            .allowsHitTesting(gameState.selectedMapStyle != .radar)
            .zIndex(0)
            
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    
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
                        .frame(minWidth: 48, minHeight: 44)
                        .contentShape(Rectangle())
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
                
                // Active Placement Mode Banner
                if let pending = gameState.pendingIndicatorPlacementType {
                    HStack(spacing: 6) {
                        TacticalIndicatorIcon(type: pending, size: 11)
                            .foregroundColor(uiThemeColor)
                        Text("TAP TO PLACE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(uiThemeColor)
                        Button(action: {
                            gameState.cancelIndicatorPlacement()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(uiThemeColor.opacity(0.8))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(uiThemeColor.opacity(0.8), lineWidth: 1)
                    )
                    .transition(.opacity)
                }
                
                Spacer()
                
                // Bottom HUD: Center/Zoom (bottom left), Ruler or KIA (bottom center), Map Style Switch (bottom right)
                HStack(alignment: .center) {
                    // Bottom left: Map centering & default zoom (all views)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            gameState.resetMapToDefaultCenterAndZoom()
                            let latDelta = gameState.currentMapSpanDelta
                            let center = gameState.locationHeadingManager.userLocation?.coordinate ?? AppConstants.Location.fallbackCoordinate
                            position = .region(
                                MKCoordinateRegion(
                                    center: center,
                                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
                                )
                            )
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(uiThemeColor)
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    
                    Spacer()
                    
                    // Bottom center: Fixed slot for both views (KIA on Radar, Ruler on MapKit)
                    Group {
                        if gameState.selectedMapStyle == .radar {
                            let themeColor = uiThemeColor
                            let buttonWidth: CGFloat = 48
                            let buttonHeight: CGFloat = 24
                            let currentBpm = gameState.healthKitManager.currentHeartRate > 0 ? gameState.healthKitManager.currentHeartRate : AppConstants.Health.defaultRestingHeartRate
                            // Scanning line sweep period using BPM/referenceBpm equation (e.g. 100 BPM = 1.0s, 75 BPM = 1.33s)
                            let sweepDuration = currentBpm > 0 ? (AppConstants.Health.referenceBpm / currentBpm) : 1.0
                            
                            TimelineView(.periodic(from: .now, by: AppConstants.Timing.DisplayRefresh.radarUIIntervalSeconds)) { timeline in
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
                                            .fill(themeColor.opacity(0.85))
                                            .frame(width: 5.5, height: 5.5)
                                            .position(dotPos)
                                            .blur(radius: 0.8)
                                        
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, AppConstants.UI.HUD.horizontalPadding)
                .padding(.bottom, AppConstants.UI.HUD.bottomPadding)
            }
            .edgesIgnoringSafeArea(.all)
            .zIndex(10)
        }
        .animation(.easeInOut(duration: 0.25), value: gameState.selectedMapStyle)
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
        .focusable()
        .digitalCrownRotation(
            $gameState.radarScaleMeters,
            from: AppConstants.UI.RadarScale.minScaleMeters,
            through: AppConstants.UI.RadarScale.maxWatchScaleMeters,
            by: AppConstants.UI.RadarScale.crownStepMeters,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        #endif
        .onChange(of: gameState.radarScaleMeters) { _, _ in
            if gameState.selectedMapStyle != .radar {
                isProgrammaticCameraChange = true
                let latDelta = gameState.currentMapSpanDelta
                let center = gameState.currentMapCenter ?? gameState.locationHeadingManager.userLocation?.coordinate ?? AppConstants.Location.fallbackCoordinate
                position = .region(
                    MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
                    )
                )
            }
        }
        .onAppear {
            gameState.locationHeadingManager.requestPermissions()
            gameState.locationHeadingManager.startUpdates()
        }
        .onDisappear {
            cancelActionHold()
        }
    }
    
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
    }
    
    private func toggleNextMapStyle() {
        switch gameState.selectedMapStyle {
        case .standard:
            gameState.selectedMapStyle = .radar
        case .radar:
            isProgrammaticCameraChange = true
            let latDelta = gameState.currentMapSpanDelta
            let center = gameState.currentMapCenter ?? gameState.locationHeadingManager.userLocation?.coordinate ?? AppConstants.Location.fallbackCoordinate
            position = .region(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(
                        latitudeDelta: latDelta,
                        longitudeDelta: latDelta
                    )
                )
            )
            gameState.selectedMapStyle = .standard
        }
    }
}
