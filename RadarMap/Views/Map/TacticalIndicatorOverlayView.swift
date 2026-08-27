import SwiftUI
import CoreLocation

// MARK: - Tactical Custom Shapes

/// Military Tactical Combat Helmet Vector Shape
public struct TacticalHelmetShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Dome curve
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.70))
        path.addCurve(
            to: CGPoint(x: w * 0.85, y: h * 0.70),
            control1: CGPoint(x: w * 0.12, y: h * 0.15),
            control2: CGPoint(x: w * 0.88, y: h * 0.15)
        )
        // Brim / chinstrap profile
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.82))
        path.closeSubpath()
        return path
    }
}

/// Military Light Vehicle / Humvee Vector Shape
public struct TacticalHumveeShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Humvee side / angled roof profile
        path.move(to: CGPoint(x: w * 0.05, y: h * 0.70))
        path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.48))
        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.44))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.24)) // Windshield angle
        path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.24)) // Roof
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.52)) // Slanted rear trunk
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.70))
        
        // Rear wheel cutout
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.70))
        path.addArc(
            center: CGPoint(x: w * 0.72, y: h * 0.70),
            radius: w * 0.10,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        // Mid chassis
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.70))
        // Front wheel cutout
        path.addArc(
            center: CGPoint(x: w * 0.28, y: h * 0.70),
            radius: w * 0.10,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.70))
        path.closeSubpath()
        return path
    }
}

/// Military Heavy Vehicle / Tank Vector Shape
public struct TacticalTankShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Gun barrel
        path.move(to: CGPoint(x: w * 0.98, y: h * 0.34))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.34))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.22)) // Turret top
        path.addLine(to: CGPoint(x: w * 0.26, y: h * 0.22))
        path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.42)) // Turret back
        path.addLine(to: CGPoint(x: w * 0.06, y: h * 0.50)) // Hull rear
        path.addLine(to: CGPoint(x: w * 0.04, y: h * 0.78)) // Tread rear curve
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.78)) // Tread front curve
        path.addLine(to: CGPoint(x: w * 0.96, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.48)) // Front hull slope
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.40))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.40))
        path.closeSubpath()
        return path
    }
}

/// Sword / Crossed Swords Vector Shape for "Attack here"
public struct TacticalSwordShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // First sword (diagonal from bottom-left to top-right)
        path.move(to: CGPoint(x: w * 0.88, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.24))
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.68))
        path.addLine(to: CGPoint(x: w * 0.34, y: h * 0.64))
        path.addLine(to: CGPoint(x: w * 0.26, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.86))
        path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.88))
        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.66))
        path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.16))
        path.closeSubpath()
        
        // Second sword (diagonal from bottom-right to top-left)
        path.move(to: CGPoint(x: w * 0.12, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.24))
        path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.68))
        path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.64))
        path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.86))
        path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.88))
        path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.66))
        path.addLine(to: CGPoint(x: w * 0.24, y: h * 0.16))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Tactical Indicator Icon Component

public struct TacticalIndicatorIcon: View {
    public let type: TacticalIndicatorType
    public let size: CGFloat
    
    public init(type: TacticalIndicatorType, size: CGFloat = 16) {
        self.type = type
        self.size = size
    }
    
    public var body: some View {
        Group {
            switch type {
            case .watchHere:
                Image(systemName: "eye.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .goHere:
                Image(systemName: "arrow.down")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .fontWeight(.black)
            case .attackHere:
                TacticalSwordShape()
            case .infantry:
                TacticalHelmetShape()
            case .lightVehicle:
                TacticalHumveeShape()
            case .heavyVehicle:
                TacticalTankShape()
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Tactical Indicator Marker View (with Hold-to-Delete countdown)

public struct TacticalIndicatorOverlayView: View {
    public let indicator: TacticalIndicator
    public let radarColor: Color
    public let onDelete: () -> Void
    
    @State private var isHolding: Bool = false
    @State private var holdProgress: Double = 0.0
    @State private var holdTimer: Timer? = nil
    @State private var holdStartTime: Date? = nil
    
    public init(
        indicator: TacticalIndicator,
        radarColor: Color,
        onDelete: @escaping () -> Void
    ) {
        self.indicator = indicator
        self.radarColor = radarColor
        self.onDelete = onDelete
    }
    
    /// Calculate color taking into account the 5-minute fade to gray rule for enemy indicators
    private var markerColor: Color {
        if indicator.category == .enemyIndicator {
            let fadeFactor = indicator.grayFadeFactor()
            if fadeFactor >= 1.0 {
                return Color.gray.opacity(0.85)
            } else if fadeFactor > 0.0 {
                // Blend radar theme color towards gray
                return radarColor.opacity(1.0 - (fadeFactor * 0.5))
            }
        }
        return radarColor
    }
    
    public var body: some View {
        let iconSize: CGFloat = 16
        let ringSize: CGFloat = 24
        let touchTargetSize: CGFloat = 44
        let fadeFactor = indicator.grayFadeFactor()
        
        ZStack {
            // Delete countdown progress ring only visible during hold
            if holdProgress > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(holdProgress))
                    .stroke(
                        Color.red.opacity(0.95),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)
            }
            
            // Center Tactical Indicator Icon (No big opaque circle background)
            TacticalIndicatorIcon(type: indicator.type, size: iconSize)
                .foregroundColor(markerColor)
                .shadow(color: Color.black.opacity(0.8), radius: 1.5, x: 0, y: 0)
                .grayscale(indicator.category == .enemyIndicator ? fadeFactor : 0.0)
        }
        .frame(width: touchTargetSize, height: touchTargetSize)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if let callsign = indicator.placedByCallsign, !callsign.isEmpty {
                Text(callsign)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(markerColor)
                    .lineLimit(1)
                    .padding(.horizontal, 2.5)
                    .padding(.vertical, 0.5)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(2)
                    .fixedSize()
                    .offset(y: 34)
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    startHold()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
        .onDisappear {
            cancelHold()
        }
    }
    
    private func startHold() {
        guard !isHolding else { return }
        isHolding = true
        holdStartTime = Date()
        holdProgress = 0.0
        
        holdTimer?.invalidate()
        let duration = AppConstants.Subscription.indicatorHoldToDeleteDurationSeconds
        let timer = Timer(timeInterval: AppConstants.UI.Gestures.holdTimerTickIntervalSeconds, repeats: true) { _ in
            guard let start = holdStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            let progress = min(1.0, elapsed / duration)
            
            withAnimation(.linear(duration: AppConstants.UI.Gestures.holdTimerTickIntervalSeconds)) {
                holdProgress = progress
            }
            
            if progress >= 1.0 {
                completeDeletion()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }
    
    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        withAnimation(.easeOut(duration: 0.2)) {
            isHolding = false
            holdProgress = 0.0
        }
    }
    
    private func completeDeletion() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        isHolding = false
        holdProgress = 0.0
        onDelete()
    }
}
