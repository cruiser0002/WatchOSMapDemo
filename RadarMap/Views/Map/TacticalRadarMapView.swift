import SwiftUI
import MapKit

public struct TacticalRadarMapView: View {
    @EnvironmentObject var gameState: GameStateManager
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingSettingsSheet: Bool = false
    @State private var currentScaleText: String = "50m"
    
    @State private var radarCenterTrigger: Int = 0
    
    // Death hold gesture states
    @State private var isHoldingRuler: Bool = false
    @State private var isChargingDeath: Bool = false
    @State private var deathProgress: Double = 0.0
    @State private var holdTimer: Timer? = nil
    @State private var holdStartTime: Date? = nil
    
    public init() {}
    
    private var squadMembers: [SquadMember] {
        guard let room = gameState.firebaseManager.activeRoom else { return [] }
        return Array(room.members.values)
    }
    
    public var body: some View {
        ZStack {
            // Tactical Map or OLED Power-Saving Radar
            if gameState.selectedMapStyle == .radar {
                SimpleRadarMapView(
                    currentScaleText: $currentScaleText,
                    centerTrigger: $radarCenterTrigger
                )
                .edgesIgnoringSafeArea(.all)
            } else {
                Map(position: $position) {
                    ForEach(squadMembers) { member in
                        Annotation(
                            member.callsign,
                            coordinate: member.coordinate,
                            anchor: .center
                        ) {
                            MemberAnnotationView(
                                member: member,
                                isMe: member.id == gameState.myMemberId
                            )
                        }
                    }
                    
                    UserAnnotation()
                }
                .mapStyle(gameState.selectedMapStyle.mapKitStyle)
                .mapControls {
                    MapCompass()
                }
                .onMapCameraChange { context in
                    updateScaleText(for: context.region)
                }
                .edgesIgnoringSafeArea(.all)
            }
            
            // Tactical HUD Overlays
            VStack {
                // Top HUD
                HStack(alignment: .center, spacing: 8) {
                    // Upper left: Config icon
                    Button(action: {
                        showingSettingsSheet = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Small KIA indicator on top when dead
                    if gameState.isDead {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Text("KIA")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .tracking(2)
                            
                            Button(action: {
                                withAnimation {
                                    gameState.setDead(false)
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("RESPAWN")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.25))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(12)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Upper right: Map style cycling
                    Button(action: {
                        toggleNextMapStyle()
                    }) {
                        Image(systemName: gameState.selectedMapStyle.iconName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                
                Spacer()
                
                // Bottom HUD: Center map (bottom left), Scale ruler & Death Loader (bottom right)
                HStack(alignment: .bottom) {
                    // Bottom left: Center map
                    Button(action: {
                        if gameState.selectedMapStyle == .radar {
                            radarCenterTrigger += 1
                        } else if let loc = gameState.locationHeadingManager.userLocation {
                            position = .region(MKCoordinateRegion(
                                center: loc.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                            ))
                        }
                    }) {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(7)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Bottom right: Scale Ruler + Death Loading Bar
                    VStack(alignment: .trailing, spacing: 4) {
                        // Loading bar that appears on top of the ruler after 1 second hold
                        if isChargingDeath {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("CONFIRMING KIA")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.red)
                                    Spacer(minLength: 4)
                                    Text("\(Int(deathProgress * 100))%")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                                .frame(width: 86)
                                
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.red.opacity(0.3))
                                        .frame(height: 5)
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.red, Color(red: 1.0, green: 0.25, blue: 0.25)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(0, 86 * CGFloat(deathProgress)), height: 5)
                                        .shadow(color: .red.opacity(0.8), radius: 2)
                                }
                                .frame(width: 86, height: 5)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.red.opacity(0.8), lineWidth: 1)
                            )
                            .cornerRadius(5)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        // Tactical Scale Ruler
                        VStack(spacing: 2) {
                            // Ruler notches
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(isHoldingRuler ? Color.red.opacity(0.9) : Color.white.opacity(0.9))
                                    .frame(width: 1.5, height: 6)
                                
                                Rectangle()
                                    .fill(isHoldingRuler ? Color.red.opacity(0.6) : Color.white.opacity(0.6))
                                    .frame(width: 18, height: 1)
                                
                                Rectangle()
                                    .fill(isHoldingRuler ? Color.red.opacity(0.9) : Color.white.opacity(0.9))
                                    .frame(width: 1, height: 4)
                                
                                Rectangle()
                                    .fill(isHoldingRuler ? Color.red.opacity(0.6) : Color.white.opacity(0.6))
                                    .frame(width: 18, height: 1)
                                
                                Rectangle()
                                    .fill(isHoldingRuler ? Color.red.opacity(0.9) : Color.white.opacity(0.9))
                                    .frame(width: 1.5, height: 6)
                            }
                            
                            Text(currentScaleText)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(isHoldingRuler ? .red : .white.opacity(0.9))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(isHoldingRuler ? Color.red.opacity(0.8) : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(5)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    startRulerHold()
                                }
                                .onEnded { _ in
                                    cancelRulerHold()
                                }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .grayscale(gameState.isDead ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.25), value: gameState.isDead)
        .animation(.easeInOut(duration: 0.2), value: isChargingDeath)
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
    }
    
    // MARK: - Hold-to-Die Timer Handling
    
    private func startRulerHold() {
        guard !gameState.isDead else { return }
        guard !isHoldingRuler else { return }
        isHoldingRuler = true
        holdStartTime = Date()
        isChargingDeath = false
        deathProgress = 0.0
        
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            guard let startTime = holdStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Hold for 1 second before the loading bar appears
            if elapsed >= 1.0 {
                if !isChargingDeath {
                    withAnimation {
                        isChargingDeath = true
                    }
                }
                
                // Loading bar fills in 3 seconds (from 1.0s to 4.0s)
                let fillElapsed = elapsed - 1.0
                deathProgress = min(1.0, fillElapsed / 3.0)
                
                if deathProgress >= 1.0 {
                    triggerDeath()
                }
            }
        }
    }
    
    private func cancelRulerHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        withAnimation {
            isHoldingRuler = false
            isChargingDeath = false
            deathProgress = 0.0
        }
    }
    
    private func triggerDeath() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        isHoldingRuler = false
        isChargingDeath = false
        deathProgress = 0.0
        withAnimation {
            gameState.setDead(true)
        }
    }
    
    private func toggleNextMapStyle() {
        switch gameState.selectedMapStyle {
        case .standard:
            gameState.selectedMapStyle = .topography
        case .topography:
            gameState.selectedMapStyle = .satellite
        case .satellite:
            gameState.selectedMapStyle = .radar
        case .radar:
            gameState.selectedMapStyle = .standard
        }
    }
    
    private func updateScaleText(for region: MKCoordinateRegion) {
        let metersPerDegreeLat = 111_139.0
        let visibleMetersLat = region.span.latitudeDelta * metersPerDegreeLat
        #if os(watchOS)
        let screenHeight: Double = 200.0
        #else
        let screenHeight: Double = 800.0
        #endif
        let rulerWidthPoints: Double = 40.0
        let rulerMeters = visibleMetersLat * (rulerWidthPoints / screenHeight)
        
        if rulerMeters < 18 {
            currentScaleText = "10m"
        } else if rulerMeters < 38 {
            currentScaleText = "25m"
        } else if rulerMeters < 75 {
            currentScaleText = "50m"
        } else if rulerMeters < 150 {
            currentScaleText = "100m"
        } else if rulerMeters < 350 {
            currentScaleText = "250m"
        } else if rulerMeters < 750 {
            currentScaleText = "500m"
        } else if rulerMeters < 1500 {
            currentScaleText = "1km"
        } else if rulerMeters < 3500 {
            currentScaleText = "2.5km"
        } else if rulerMeters < 7500 {
            currentScaleText = "5km"
        } else if rulerMeters < 15000 {
            currentScaleText = "10km"
        } else {
            currentScaleText = "\(max(1, Int(round(rulerMeters / 1000.0))))km"
        }
    }
}
