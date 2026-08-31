import SwiftUI
import MapKit
#if canImport(UIKit)
import UIKit
#endif

/// Standard Native MapKit View for full topographic and geographic navigation with custom tactical annotations and Crown zoom.
public struct StandardMapView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Binding var lastCameraCenterCoordinate: CLLocationCoordinate2D?
    let onRequestCrownFocus: () -> Void
    
    @State private var position: MapCameraPosition
    @State private var currentCameraDistance: Double
    @State private var hasSettledInitialCamera: Bool = false
    @State private var userDidPan: Bool = false
    @State private var baseScale: Double = AppConstants.UI.RadarScale.defaultScaleMeters
    
    public init(
        gameState: GameStateManager,
        lastCameraCenterCoordinate: Binding<CLLocationCoordinate2D?>,
        onRequestCrownFocus: @escaping () -> Void = {}
    ) {
        self._lastCameraCenterCoordinate = lastCameraCenterCoordinate
        self.onRequestCrownFocus = onRequestCrownFocus
        
        let scale = gameState.mapStateMachine.scaleMeters
        let distance = AppConstants.UI.RadarScale.cameraDistance(forScale: scale)
        let center = gameState.mapStateMachine.effectiveCenter(userCoord: gameState.localPlayerMember.coordinate)
        let camera = MapCamera(centerCoordinate: center, distance: distance, heading: 0, pitch: 0)
        self._position = State(initialValue: .camera(camera))
        self._currentCameraDistance = State(initialValue: distance)
    }
    
    private var otherSquadMembers: [SquadMember] {
        gameState.otherSquadMembers
    }
    
    private var meMember: SquadMember {
        gameState.localPlayerMember
    }
    
    private var radarThemeColor: Color {
        gameState.radarColorTheme.color
    }
    
    private var cameraBounds: MapCameraBounds {
        #if os(watchOS)
        let distance = AppConstants.UI.RadarScale.cameraDistance(forScale: gameState.mapStateMachine.scaleMeters)
        if gameState.mapStateMachine.trackingState.isLocked {
            return MapCameraBounds(minimumDistance: distance, maximumDistance: distance)
        } else {
            return MapCameraBounds(minimumDistance: 1, maximumDistance: 25000)
        }
        #else
        let minDistance = AppConstants.UI.RadarScale.cameraDistance(forScale: AppConstants.UI.RadarScale.minScaleMeters)
        let maxDistance = AppConstants.UI.RadarScale.cameraDistance(forScale: AppConstants.UI.RadarScale.maxiOSScaleMeters)
        return MapCameraBounds(minimumDistance: minDistance, maximumDistance: maxDistance)
        #endif
    }
    
    public static func cameraDistance(forScale scaleMeters: Double) -> Double {
        AppConstants.UI.RadarScale.cameraDistance(forScale: scaleMeters)
    }
    
    public var body: some View {
        MapReader { proxy in
            Map(
                position: $position,
                bounds: cameraBounds,
                interactionModes: {
                    #if os(watchOS)
                    return .pan
                    #else
                    return [.pan, .zoom]
                    #endif
                }()
            ) {
                // Remote Teammate Annotations
                ForEach(otherSquadMembers, id: \.id) { member in
                    Annotation(
                        member.callsign,
                        coordinate: member.coordinate,
                        anchor: .center
                    ) {
                        MemberAnnotationView(
                            member: member,
                            isMe: false,
                            radarColor: radarThemeColor
                        )
                        .animation(.linear(duration: 0), value: member.coordinate)
                    }
                    .annotationTitles(.hidden)
                }
                
                // Tactical Indicators
                ForEach(gameState.allTacticalIndicators, id: \.id) { indicator in
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
                
                // CRITICAL RULE: NEVER CHANGE "ME" FROM UserAnnotation TO Annotation.
                // UserAnnotation is required to suppress MapKit's default native blue dot and replace it with our custom vector icon.
                UserAnnotation {
                    MemberAnnotationView(
                        member: meMember,
                        isMe: true,
                        radarColor: radarThemeColor
                    )
                }
            }
            .mapStyle(gameState.selectedMapStyle.mapKitStyle)
            .mapControls { }
            .onMapCameraChange(frequency: .continuous) { context in
                #if !os(watchOS)
                guard hasSettledInitialCamera else { return }
                currentCameraDistance = context.camera.distance
                let liveScale = AppConstants.UI.RadarScale.scaleMeters(forCameraDistance: context.camera.distance)
                if abs(gameState.radarScaleMeters - liveScale) > 0.01 {
                    gameState.radarScaleMeters = liveScale
                }
                #endif
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                let center = context.camera.centerCoordinate
                lastCameraCenterCoordinate = center
                
                guard hasSettledInitialCamera else { return }
                currentCameraDistance = context.camera.distance
                
                #if !os(watchOS)
                let currentScale = AppConstants.UI.RadarScale.scaleMeters(forCameraDistance: context.camera.distance)
                let snappedScale = AppConstants.UI.RadarScale.snapToDiscreteScale(currentScale)
                let userCoord = gameState.localPlayerMember.coordinate
                
                gameState.sendMapAction(.pan(to: center, userCoord: userCoord))
                
                let targetDistance = AppConstants.UI.RadarScale.cameraDistance(forScale: snappedScale)
                if abs(context.camera.distance - targetDistance) > 1.0 {
                    gameState.sendMapAction(.setScale(meters: snappedScale))
                    currentCameraDistance = targetDistance
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        let targetCenter = gameState.mapStateMachine.effectiveCenter(userCoord: userCoord)
                        let camera = MapCamera(centerCoordinate: targetCenter, distance: targetDistance, heading: 0, pitch: 0)
                        position = .camera(camera)
                    }
                }
                onRequestCrownFocus()
                #else
                if userDidPan {
                    userDidPan = false
                    let userCoord = gameState.localPlayerMember.coordinate
                    gameState.sendMapAction(.pan(to: center, userCoord: userCoord))
                    onRequestCrownFocus()
                }
                #endif
            }
            .onTapGesture { screenPoint in
                if gameState.pendingIndicatorPlacementType != nil,
                   let coordinate = proxy.convert(screenPoint, from: .local) {
                    gameState.placeTacticalIndicator(at: coordinate)
                }
            }
            #if os(watchOS)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        userDidPan = true
                    }
                    .onEnded { _ in
                        onRequestCrownFocus()
                    }
            )
            #endif
            .edgesIgnoringSafeArea(.all)
        }
        .edgesIgnoringSafeArea(.all)
        .onChange(of: gameState.mapStateMachine.scaleMeters) { _, newScale in
            baseScale = newScale
            let targetDistance = AppConstants.UI.RadarScale.cameraDistance(forScale: newScale)
            if abs(currentCameraDistance - targetDistance) > 2.0 {
                currentCameraDistance = targetDistance
                let targetCenter = gameState.mapStateMachine.effectiveCenter(userCoord: meMember.coordinate)
                let camera = MapCamera(centerCoordinate: targetCenter, distance: targetDistance, heading: 0, pitch: 0)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    position = .camera(camera)
                }
            }
        }
        .onChange(of: gameState.mapStateMachine.centerTriggerCount) { _, _ in
            let userCoord = meMember.coordinate
            lastCameraCenterCoordinate = userCoord
            userDidPan = false
            let distance = AppConstants.UI.RadarScale.cameraDistance(forScale: gameState.mapStateMachine.scaleMeters)
            currentCameraDistance = distance
            let camera = MapCamera(centerCoordinate: userCoord, distance: distance, heading: 0, pitch: 0)
            withAnimation(.easeInOut(duration: 0.25)) {
                position = .camera(camera)
            }
        }
        .onChange(of: gameState.mapStateMachine.trackingState) { _, state in
            let distance = AppConstants.UI.RadarScale.cameraDistance(forScale: gameState.mapStateMachine.scaleMeters)
            let targetCenter = state.isLocked ? meMember.coordinate : (state.pannedCoordinate ?? meMember.coordinate)
            lastCameraCenterCoordinate = targetCenter
            if state.isLocked && abs(currentCameraDistance - distance) > 2.0 {
                currentCameraDistance = distance
                let camera = MapCamera(centerCoordinate: targetCenter, distance: distance, heading: 0, pitch: 0)
                withAnimation(.easeInOut(duration: 0.25)) {
                    position = .camera(camera)
                }
            }
        }
        .onAppear {
            hasSettledInitialCamera = false
            baseScale = gameState.mapStateMachine.scaleMeters
            userDidPan = false
            let distance = AppConstants.UI.RadarScale.cameraDistance(forScale: gameState.mapStateMachine.scaleMeters)
            currentCameraDistance = distance
            let targetCenter = gameState.mapStateMachine.effectiveCenter(userCoord: meMember.coordinate)
            lastCameraCenterCoordinate = targetCenter
            let camera = MapCamera(centerCoordinate: targetCenter, distance: distance, heading: 0, pitch: 0)
            position = .camera(camera)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                hasSettledInitialCamera = true
            }
        }
    }
}
