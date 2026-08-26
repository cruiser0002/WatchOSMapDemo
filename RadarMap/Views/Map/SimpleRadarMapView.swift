import SwiftUI
import CoreLocation

public struct SimpleRadarMapView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Binding var currentScaleText: String
    @Binding var centerTrigger: Int
    
    // Zoom and Pan State
    @State private var radarScaleMeters: Double = 100.0 // Radius in meters
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var baseScale: Double = 100.0
    
    public init(currentScaleText: Binding<String>, centerTrigger: Binding<Int> = .constant(0)) {
        self._currentScaleText = currentScaleText
        self._centerTrigger = centerTrigger
    }
    
    private var squadMembers: [SquadMember] {
        guard let room = gameState.firebaseManager.activeRoom else { return [] }
        return Array(room.members.values)
    }
    
    private var userCoordinate: CLLocationCoordinate2D {
        if let loc = gameState.locationHeadingManager.userLocation?.coordinate {
            return loc
        }
        if let myMember = gameState.firebaseManager.activeRoom?.members[gameState.myMemberId] {
            return myMember.coordinate
        }
        return CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417)
    }
    
    private var userHeading: Double {
        gameState.locationHeadingManager.userHeading?.trueHeading ?? 0.0
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            let mapCenter = CGPoint(
                x: screenCenter.x + accumulatedOffset.width + dragOffset.width,
                y: screenCenter.y + accumulatedOffset.height + dragOffset.height
            )
            let maxRadius = min(size.width, size.height) * 0.44
            
            ZStack {
                // Maximum Black Background for OLED Power Conservation
                Color.black
                    .edgesIgnoringSafeArea(.all)
                
                let themeColor = gameState.radarColorTheme.color
                
                // Concentric Tactical Range Rings (Red or Green)
                ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { ratio in
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
                    let length = maxRadius * 1.05
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
                    let plusSize: CGFloat = 9
                    path.move(to: CGPoint(x: screenCenter.x - plusSize, y: screenCenter.y))
                    path.addLine(to: CGPoint(x: screenCenter.x + plusSize, y: screenCenter.y))
                    path.move(to: CGPoint(x: screenCenter.x, y: screenCenter.y - plusSize))
                    path.addLine(to: CGPoint(x: screenCenter.x, y: screenCenter.y + plusSize))
                }
                .stroke(themeColor, lineWidth: 2.0)
                
                // Range Ring Distance Labels
                ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { ratio in
                    let ringDist = radarScaleMeters * ratio
                    Text(formatDistance(meters: ringDist))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(themeColor.opacity(0.8))
                        .position(x: screenCenter.x + 18, y: screenCenter.y - (maxRadius * ratio) + 6)
                }
                
                // Active Squad Members
                ForEach(squadMembers) { member in
                    let isMe = member.id == gameState.myMemberId
                    let offset = pointOffset(for: member.coordinate, userCoord: userCoordinate, maxRadius: maxRadius, rangeMeters: radarScaleMeters)
                    
                    MemberAnnotationView(member: member, isMe: isMe)
                        .position(x: mapCenter.x + offset.x, y: mapCenter.y + offset.y)
                        .animation(.easeInOut(duration: 0.35), value: member.coordinate.latitude)
                        .animation(.easeInOut(duration: 0.35), value: member.coordinate.longitude)
                        .animation(.easeInOut(duration: 0.35), value: member.heading)
                }
                
                // If local user is solo/host without squad list, render center operator arrow blip
                if !squadMembers.contains(where: { $0.id == gameState.myMemberId }) {
                    let myHr = gameState.healthKitManager.currentHeartRate > 0 ? gameState.healthKitManager.currentHeartRate : 75.0
                    let themeColor = gameState.radarColorTheme.color
                    
                    ZStack {
                        SquadPlayerShape()
                            .fill(themeColor)
                            .overlay(
                                SquadPlayerShape()
                                    .stroke(Color.white, lineWidth: 1.2)
                            )
                            .frame(width: 20, height: 20)
                            .rotationEffect(.degrees(userHeading))
                            .overlay(
                                SquadPulseCore(heartRate: myHr, tintColor: .white)
                                    .frame(width: 6, height: 6)
                            )
                    }
                    .position(mapCenter)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        accumulatedOffset.width += value.translation.width
                        accumulatedOffset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
            #if os(watchOS)
            .focusable()
            .digitalCrownRotation(
                $radarScaleMeters,
                from: 10.0,
                through: 5000.0,
                by: 10.0,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: radarScaleMeters) { _, _ in
                updateScaleText(maxRadius: maxRadius)
            }
            #else
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let newScale = baseScale / scale
                        radarScaleMeters = min(max(newScale, 10.0), 20000.0)
                        updateScaleText(maxRadius: maxRadius)
                    }
                    .onEnded { _ in
                        baseScale = radarScaleMeters
                    }
            )
            #endif
            .onChange(of: centerTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    accumulatedOffset = .zero
                    dragOffset = .zero
                }
            }
            .onAppear {
                updateScaleText(maxRadius: maxRadius)
            }
        }
    }
    
    private func pointOffset(for target: CLLocationCoordinate2D, userCoord: CLLocationCoordinate2D, maxRadius: CGFloat, rangeMeters: Double) -> CGPoint {
        let dLat = target.latitude - userCoord.latitude
        let dLon = target.longitude - userCoord.longitude
        
        let metersNorth = dLat * 111_139.0
        let metersEast = dLon * (111_139.0 * cos(userCoord.latitude * .pi / 180.0))
        
        let pointsPerMeter = Double(maxRadius) / rangeMeters
        let x = CGFloat(metersEast * pointsPerMeter)
        let y = CGFloat(-metersNorth * pointsPerMeter)
        
        return CGPoint(x: x, y: y)
    }
    
    private func formatDistance(meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(round(meters)))m"
        } else {
            let km = meters / 1000.0
            return String(format: "%.1fkm", km)
        }
    }
    
    private func updateScaleText(maxRadius: CGFloat) {
        guard maxRadius > 0 else { return }
        let rulerWidthPoints: Double = 40.0
        let rulerMeters = rulerWidthPoints * (radarScaleMeters / Double(maxRadius))
        currentScaleText = formatRulerDistance(meters: rulerMeters)
    }
    
    private func formatRulerDistance(meters: Double) -> String {
        if meters < 18 {
            return "10m"
        } else if meters < 38 {
            return "25m"
        } else if meters < 75 {
            return "50m"
        } else if meters < 150 {
            return "100m"
        } else if meters < 350 {
            return "250m"
        } else if meters < 750 {
            return "500m"
        } else if meters < 1500 {
            return "1km"
        } else if meters < 3500 {
            return "2.5km"
        } else if meters < 7500 {
            return "5km"
        } else {
            return "\(max(1, Int(round(meters / 1000.0))))km"
        }
    }
}
