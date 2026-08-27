import SwiftUI

public extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let length = hexSanitized.count
        let r, g, b, a: Double
        if length == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Vector shape for standard Squad player icon (circle with a forward-pointing nose at 12 o'clock)
public struct SquadPlayerShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        let center = CGPoint(x: width / 2, y: height / 2)
        let radius = min(width, height) * AppConstants.UI.TacticalShapes.playerRadiusFactor
        
        // Circular base body with forward pointing nose
        let noseTip = CGPoint(x: width / 2, y: 0)
        let leftShoulderAngle = Angle(degrees: AppConstants.UI.TacticalShapes.playerLeftShoulderAngleDegrees)
        let rightShoulderAngle = Angle(degrees: AppConstants.UI.TacticalShapes.playerRightShoulderAngleDegrees)
        
        let rightShoulder = CGPoint(
            x: center.x + radius * CGFloat(cos(rightShoulderAngle.radians)),
            y: center.y + radius * CGFloat(sin(rightShoulderAngle.radians))
        )
        let leftShoulder = CGPoint(
            x: center.x + radius * CGFloat(cos(leftShoulderAngle.radians)),
            y: center.y + radius * CGFloat(sin(leftShoulderAngle.radians))
        )
        
        path.move(to: noseTip)
        path.addLine(to: rightShoulder)
        // Arc around the base (bottom) to the left shoulder in increasing angle direction
        path.addArc(
            center: center,
            radius: radius,
            startAngle: rightShoulderAngle,
            endAngle: leftShoulderAngle,
            clockwise: false
        )
        path.addLine(to: leftShoulder)
        path.addLine(to: noseTip)
        path.closeSubpath()
        
        return path
    }
}

/// Vector shape for Squad Leader (SL) icon (Directional forward nose with SL command chevron wings)
public struct SquadLeaderShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        let center = CGPoint(x: w / 2, y: h / 2)
        let radius = min(w, h) * AppConstants.UI.TacticalShapes.leaderRadiusFactor
        
        // Top forward pointy nose
        let noseTip = CGPoint(x: w / 2, y: 0)
        
        let rightShoulder = CGPoint(x: center.x + radius * AppConstants.UI.TacticalShapes.leaderShoulderOffsetRatio, y: center.y - radius * AppConstants.UI.TacticalShapes.leaderShoulderHeightRatio)
        let rightWingOut = CGPoint(x: w * AppConstants.UI.TacticalShapes.leaderWingOuterRatio, y: center.y + radius * AppConstants.UI.TacticalShapes.leaderWingHeightRatio)
        let rightWingIn = CGPoint(
            x: center.x + radius * CGFloat(cos(Angle(degrees: AppConstants.UI.TacticalShapes.leaderInnerNotchAngle1Degrees).radians)),
            y: center.y + radius * CGFloat(sin(Angle(degrees: AppConstants.UI.TacticalShapes.leaderInnerNotchAngle1Degrees).radians))
        )
        
        let leftShoulder = CGPoint(x: center.x - radius * AppConstants.UI.TacticalShapes.leaderShoulderOffsetRatio, y: center.y - radius * AppConstants.UI.TacticalShapes.leaderShoulderHeightRatio)
        let leftWingOut = CGPoint(x: w * (1.0 - AppConstants.UI.TacticalShapes.leaderWingOuterRatio), y: center.y + radius * AppConstants.UI.TacticalShapes.leaderWingHeightRatio)
        let leftWingIn = CGPoint(
            x: center.x + radius * CGFloat(cos(Angle(degrees: AppConstants.UI.TacticalShapes.leaderInnerNotchAngle2Degrees).radians)),
            y: center.y + radius * CGFloat(sin(Angle(degrees: AppConstants.UI.TacticalShapes.leaderInnerNotchAngle2Degrees).radians))
        )
        
        path.move(to: noseTip)
        path.addLine(to: rightShoulder)
        path.addLine(to: rightWingOut)
        path.addLine(to: rightWingIn)
        
        // Bottom arc connecting the inner chevron notches (35° -> 90° -> 145°)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: Angle(degrees: AppConstants.UI.TacticalShapes.leaderInnerNotchAngle1Degrees),
            endAngle: Angle(degrees: AppConstants.UI.TacticalShapes.leaderInnerNotchAngle2Degrees),
            clockwise: false
        )
        
        path.addLine(to: leftWingIn)
        path.addLine(to: leftWingOut)
        path.addLine(to: leftShoulder)
        path.addLine(to: noseTip)
        path.closeSubpath()
        
        return path
    }
}

/// Vector shape for KIA / Dead player ("X" icon) as a single continuous 12-point polygon
public struct SquadDeadXShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h / 2
        
        let armLength = min(w, h) * AppConstants.UI.TacticalShapes.deadXArmLengthRatio
        let halfThick = min(w, h) * AppConstants.UI.TacticalShapes.deadXHalfThicknessRatio
        let sqrt2 = AppConstants.UI.TacticalShapes.sqrtTwo
        
        let lMinusT = (armLength - halfThick) / sqrt2
        let lPlusT = (armLength + halfThick) / sqrt2
        let tDiag = halfThick * sqrt2
        
        // 12 vertices of a single continuous "X" polygon
        path.move(to: CGPoint(x: cx, y: cy - tDiag))                               // Top inner crook
        path.addLine(to: CGPoint(x: cx + lMinusT, y: cy - lPlusT))                 // Top-Right arm top corner
        path.addLine(to: CGPoint(x: cx + lPlusT, y: cy - lMinusT))                 // Top-Right arm right corner
        path.addLine(to: CGPoint(x: cx + tDiag, y: cy))                            // Right inner crook
        path.addLine(to: CGPoint(x: cx + lPlusT, y: cy + lMinusT))                 // Bottom-Right arm right corner
        path.addLine(to: CGPoint(x: cx + lMinusT, y: cy + lPlusT))                 // Bottom-Right arm bottom corner
        path.addLine(to: CGPoint(x: cx, y: cy + tDiag))                            // Bottom inner crook
        path.addLine(to: CGPoint(x: cx - lMinusT, y: cy + lPlusT))                 // Bottom-Left arm bottom corner
        path.addLine(to: CGPoint(x: cx - lPlusT, y: cy + lMinusT))                 // Bottom-Left arm left corner
        path.addLine(to: CGPoint(x: cx - tDiag, y: cy))                            // Left inner crook
        path.addLine(to: CGPoint(x: cx - lPlusT, y: cy - lMinusT))                 // Top-Left arm left corner
        path.addLine(to: CGPoint(x: cx - lMinusT, y: cy - lPlusT))                 // Top-Left arm top corner
        path.closeSubpath()
        
        return path
    }
}

/// Heart rate core pulsator that scales and pulses at a frequency proportional to (BPM / 100)
public struct SquadPulseCore: View {
    public let heartRate: Double
    public let tintColor: Color
    
    @State private var isPulsing: Bool = false
    
    public init(heartRate: Double, tintColor: Color) {
        self.heartRate = heartRate
        self.tintColor = tintColor
    }
    
    // Pulse animation cycle duration in seconds:
    // When BPM is 100, duration is 0.6s (1 beat); scaled by (60 / BPM)
    private var pulseDuration: Double {
        guard heartRate > 0 else { return 1.0 }
        let clampedBpm = max(min(heartRate, AppConstants.Health.maxPulseBpm), AppConstants.Health.minPulseBpm)
        return AppConstants.Timing.secondsPerMinute / clampedBpm
    }
    
    public var body: some View {
        ZStack {
            if heartRate > 0 {
                // Expanding pulse ring (breathing circle)
                Circle()
                    .stroke(tintColor.opacity(isPulsing ? 0.0 : 0.8), lineWidth: 1.2)
                    .scaleEffect(isPulsing ? 1.9 : 0.8, anchor: .center)
                
                // Solid center core dot (player dot)
                Circle()
                    .fill(tintColor)
                    .scaleEffect(isPulsing ? 1.2 : 0.8, anchor: .center)
            }
        }
        .onAppear {
            startPulsing()
        }
        .onChange(of: heartRate) { _, _ in
            startPulsing()
        }
    }
    
    private func startPulsing() {
        guard heartRate > 0 else {
            isPulsing = false
            return
        }
        withAnimation(
            Animation.easeInOut(duration: pulseDuration / 2)
                .repeatForever(autoreverses: true)
        ) {
            isPulsing = true
        }
    }
}

/// Vector shape for ECG heartbeat pulse wave (or flatline when KIA / downed)
public struct ECGWaveShape: Shape {
    public var isFlatline: Bool
    
    public init(isFlatline: Bool = false) {
        self.isFlatline = isFlatline
    }
    
    public var animatableData: Double {
        get { isFlatline ? 1.0 : 0.0 }
        set { isFlatline = newValue >= 0.5 }
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let midY = h / 2
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        if isFlatline {
            path.addLine(to: CGPoint(x: w, y: midY))
        } else {
            // ECG pulse wave: baseline -> P wave -> Q dip -> R peak -> S dip -> T wave -> baseline
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.pWaveStart, y: midY))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.pWavePeak, y: midY - h * AppConstants.UI.TacticalShapes.ECG.pWaveHeightRatio))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.pWaveEnd, y: midY))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.qDip, y: midY + h * AppConstants.UI.TacticalShapes.ECG.qDipDepthRatio))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.rPeak, y: midY - h * AppConstants.UI.TacticalShapes.ECG.rPeakHeightRatio))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.sDip, y: midY + h * AppConstants.UI.TacticalShapes.ECG.sDipDepthRatio))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.tWaveStart, y: midY))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.tWavePeak, y: midY - h * AppConstants.UI.TacticalShapes.ECG.tWaveHeightRatio))
            path.addLine(to: CGPoint(x: w * AppConstants.UI.TacticalShapes.ECG.tWaveEnd, y: midY))
            path.addLine(to: CGPoint(x: w, y: midY))
        }
        
        return path
    }
    
    /// Computes (x, y) point on the ECG curve for a normalized progress in [0, 1]
    public static func point(at progress: CGFloat, in size: CGSize, isFlatline: Bool = false) -> CGPoint {
        let t = min(max(progress, 0.0), 1.0)
        let midY = size.height / 2.0
        let x = t * size.width
        if isFlatline {
            return CGPoint(x: x, y: midY)
        }
        let h = size.height
        
        let y: CGFloat
        let ecg = AppConstants.UI.TacticalShapes.ECG.self
        if t < ecg.pWaveStart {
            y = midY
        } else if t < ecg.pWavePeak {
            let frac = (t - ecg.pWaveStart) / (ecg.pWavePeak - ecg.pWaveStart)
            y = midY - (h * ecg.pWaveHeightRatio) * frac
        } else if t < ecg.pWaveEnd {
            let frac = (t - ecg.pWavePeak) / (ecg.pWaveEnd - ecg.pWavePeak)
            y = (midY - h * ecg.pWaveHeightRatio) + (h * ecg.pWaveHeightRatio) * frac
        } else if t < ecg.qDip {
            let frac = (t - ecg.pWaveEnd) / (ecg.qDip - ecg.pWaveEnd)
            y = midY + (h * ecg.qDipDepthRatio) * frac
        } else if t < ecg.rPeak {
            let frac = (t - ecg.qDip) / (ecg.rPeak - ecg.qDip)
            let startY = midY + h * ecg.qDipDepthRatio
            let endY = midY - h * ecg.rPeakHeightRatio
            y = startY + (endY - startY) * frac
        } else if t < ecg.sDip {
            let frac = (t - ecg.rPeak) / (ecg.sDip - ecg.rPeak)
            let startY = midY - h * ecg.rPeakHeightRatio
            let endY = midY + h * ecg.sDipDepthRatio
            y = startY + (endY - startY) * frac
        } else if t < ecg.tWaveStart {
            let frac = (t - ecg.sDip) / (ecg.tWaveStart - ecg.sDip)
            let startY = midY + h * ecg.sDipDepthRatio
            let endY = midY
            y = startY + (endY - startY) * frac
        } else if t < ecg.tWavePeak {
            let frac = (t - ecg.tWaveStart) / (ecg.tWavePeak - ecg.tWaveStart)
            let startY = midY - h * ecg.tWaveHeightRatio
            let endY = midY
            y = startY + (endY - startY) * frac
        } else if t < ecg.tWaveEnd {
            let frac = (t - ecg.tWavePeak) / (ecg.tWaveEnd - ecg.tWavePeak)
            y = (midY - h * ecg.tWaveHeightRatio) + (h * ecg.tWaveHeightRatio) * frac
        } else {
            y = midY
        }
        return CGPoint(x: x, y: y)
    }
}

