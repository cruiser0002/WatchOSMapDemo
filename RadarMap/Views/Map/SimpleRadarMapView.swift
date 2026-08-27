import SwiftUI
import CoreLocation

public struct SimpleRadarMapView: View {
    @EnvironmentObject var gameState: GameStateManager
    
    // Pan State
    @State private var dragOffset: CGSize = .zero
    @State private var baseScale: Double = AppConstants.UI.RadarScale.defaultScaleMeters
    
    public init() {}
    
    private var otherSquadMembers: [SquadMember] {
        guard let room = gameState.firebaseManager.activeRoom else { return [] }
        return room.members.values.filter { $0.id != gameState.myMemberId }
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            let meMember = gameState.localPlayerMember
            let centerCoord = gameState.currentMapCenter ?? meMember.coordinate
            let centerPoint = CGPoint(
                x: screenCenter.x + dragOffset.width,
                y: screenCenter.y + dragOffset.height
            )
            let maxRadius = min(size.width, size.height) * AppConstants.UI.RadarScale.radarRadiusRatio
            
            let metersPerDegreeLat = AppConstants.Location.metersPerDegreeLatitude
            let metersPerDegreeLon = metersPerDegreeLat * cos(centerCoord.latitude * AppConstants.Location.degreesToRadiansFactor)
            let pointsPerMeter = gameState.radarScaleMeters > 0 ? Double(maxRadius) / gameState.radarScaleMeters : 1.0
            
            ZStack {
                // Maximum Black Background for OLED Power Conservation
                Color.black
                    .edgesIgnoringSafeArea(.all)
                
                let themeColor = gameState.radarColorTheme.color
                
                // Concentric Tactical Range Rings (Red or Green)
                ForEach(AppConstants.UI.RadarScale.rangeRingRatios, id: \.self) { ratio in
                    Circle()
                        .stroke(
                            ratio == 1.0 ? themeColor.opacity(0.85) : themeColor.opacity(0.4),
                            lineWidth: ratio == 1.0 ? 1.5 : 1.0
                        )
                        .frame(width: maxRadius * 2 * ratio, height: maxRadius * 2 * ratio)
                        .position(screenCenter)
                }
                
                // Full Diameter Crosshair (+)
                Path { path in
                    let length = maxRadius * AppConstants.UI.RadarScale.crosshairExtensionRatio
                    // Horizontal axis
                    path.move(to: CGPoint(x: screenCenter.x - length, y: screenCenter.y))
                    path.addLine(to: CGPoint(x: screenCenter.x + length, y: screenCenter.y))
                    // Vertical axis
                    path.move(to: CGPoint(x: screenCenter.x, y: screenCenter.y - length))
                    path.addLine(to: CGPoint(x: screenCenter.x, y: screenCenter.y + length))
                }
                .stroke(themeColor.opacity(0.45), lineWidth: 1.0)
                
                // Bold Center '+' Reticle
                Path { path in
                    let plusSize: CGFloat = CGFloat(AppConstants.UI.RadarScale.centerReticleSize)
                    path.move(to: CGPoint(x: screenCenter.x - plusSize, y: screenCenter.y))
                    path.addLine(to: CGPoint(x: screenCenter.x + plusSize, y: screenCenter.y))
                    path.move(to: CGPoint(x: screenCenter.x, y: screenCenter.y - plusSize))
                    path.addLine(to: CGPoint(x: screenCenter.x, y: screenCenter.y + plusSize))
                }
                .stroke(themeColor, lineWidth: 2.0)
                
                // Range Ring Distance Labels
                ForEach(AppConstants.UI.RadarScale.rangeRingRatios, id: \.self) { ratio in
                    let ringDist = gameState.radarScaleMeters * ratio
                    Text(AppConstants.UI.ScaleRuler.formatDistance(meters: ringDist))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(themeColor.opacity(0.8))
                        .position(x: screenCenter.x + 18, y: screenCenter.y - (maxRadius * ratio) + 6)
                }
                
                // Active Remote Squad Members (Smooth 60 FPS Gliding & Rotation)
                ForEach(otherSquadMembers, id: \.id) { member in
                    let smoothed = gameState.deadReckoningEngine.smoothedMember(for: member)
                    let offset = pointOffset(for: smoothed.coordinate, centerCoord: centerCoord, metersPerDegreeLat: metersPerDegreeLat, metersPerDegreeLon: metersPerDegreeLon, pointsPerMeter: pointsPerMeter)
                    
                    MemberAnnotationView(
                        member: smoothed,
                        isMe: false,
                        radarColor: themeColor
                    )
                        .position(x: centerPoint.x + offset.x, y: centerPoint.y + offset.y)
                }
                
                // Active Tactical Indicators (Orders & Enemy markers)
                ForEach(gameState.allTacticalIndicators) { indicator in
                    let offset = pointOffset(for: indicator.coordinate, centerCoord: centerCoord, metersPerDegreeLat: metersPerDegreeLat, metersPerDegreeLon: metersPerDegreeLon, pointsPerMeter: pointsPerMeter)
                    
                    TacticalIndicatorOverlayView(
                        indicator: indicator,
                        radarColor: themeColor,
                        onDelete: {
                            gameState.removeTacticalIndicator(id: indicator.id)
                        }
                    )
                    .position(x: centerPoint.x + offset.x, y: centerPoint.y + offset.y)
                    .zIndex(5)
                }
                
                // Local Player "Me" Indicator (Always live position + live COD blended heading)
                let meOffset = pointOffset(for: meMember.coordinate, centerCoord: centerCoord, metersPerDegreeLat: metersPerDegreeLat, metersPerDegreeLon: metersPerDegreeLon, pointsPerMeter: pointsPerMeter)
                MemberAnnotationView(
                    member: meMember,
                    isMe: true,
                    radarColor: themeColor
                )
                .position(x: centerPoint.x + meOffset.x, y: centerPoint.y + meOffset.y)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if gameState.pendingIndicatorPlacementType != nil {
                    let tappedCoord = coordinate(
                        for: location,
                        centerScreenPoint: centerPoint,
                        centerCoord: centerCoord,
                        metersPerDegreeLat: metersPerDegreeLat,
                        metersPerDegreeLon: metersPerDegreeLon,
                        pointsPerMeter: pointsPerMeter
                    )
                    gameState.placeTacticalIndicator(at: tappedCoord)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let endCenter = coordinate(
                            for: CGPoint(x: screenCenter.x - value.translation.width, y: screenCenter.y - value.translation.height),
                            centerScreenPoint: screenCenter,
                            centerCoord: centerCoord,
                            metersPerDegreeLat: metersPerDegreeLat,
                            metersPerDegreeLon: metersPerDegreeLon,
                            pointsPerMeter: pointsPerMeter
                        )
                        gameState.currentMapCenter = endCenter
                        dragOffset = .zero
                    }
            )
            #if !os(watchOS)
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let newScale = baseScale / scale
                        gameState.radarScaleMeters = min(max(newScale, AppConstants.UI.RadarScale.minScaleMeters), AppConstants.UI.RadarScale.maxiOSScaleMeters)
                    }
                    .onEnded { _ in
                        baseScale = gameState.radarScaleMeters
                    }
            )
            #endif
            .onChange(of: gameState.radarCenterTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    dragOffset = .zero
                    baseScale = AppConstants.UI.RadarScale.defaultScaleMeters
                }
            }
            .onAppear {
                baseScale = gameState.radarScaleMeters
            }
        }
    }
    
    private func pointOffset(for target: CLLocationCoordinate2D, centerCoord: CLLocationCoordinate2D, metersPerDegreeLat: Double, metersPerDegreeLon: Double, pointsPerMeter: Double) -> CGPoint {
        let dLat = target.latitude - centerCoord.latitude
        let dLon = target.longitude - centerCoord.longitude
        
        let metersEast = dLon * metersPerDegreeLon
        let metersNorth = dLat * metersPerDegreeLat
        
        let x = CGFloat(metersEast * pointsPerMeter)
        let y = CGFloat(-metersNorth * pointsPerMeter)
        
        return CGPoint(x: x, y: y)
    }
    
    private func coordinate(for screenPoint: CGPoint, centerScreenPoint: CGPoint, centerCoord: CLLocationCoordinate2D, metersPerDegreeLat: Double, metersPerDegreeLon: Double, pointsPerMeter: Double) -> CLLocationCoordinate2D {
        let dx = screenPoint.x - centerScreenPoint.x
        let dy = screenPoint.y - centerScreenPoint.y
        
        guard pointsPerMeter > 0 else { return centerCoord }
        
        let metersEast = Double(dx) / pointsPerMeter
        let metersNorth = Double(-dy) / pointsPerMeter
        
        let latDelta = metersNorth / metersPerDegreeLat
        let lonDelta = metersEast / metersPerDegreeLon
        
        return CLLocationCoordinate2D(
            latitude: centerCoord.latitude + latDelta,
            longitude: centerCoord.longitude + lonDelta
        )
    }
}
