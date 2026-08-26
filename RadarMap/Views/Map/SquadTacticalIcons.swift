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
        let radius = min(width, height) * 0.38
        
        // Circular base body with forward pointing nose
        let noseTip = CGPoint(x: width / 2, y: 0)
        let leftShoulderAngle = Angle(degrees: 220)
        let rightShoulderAngle = Angle(degrees: 320)
        
        let rightShoulder = CGPoint(
            x: center.x + radius * CGFloat(cos(rightShoulderAngle.radians)),
            y: center.y + radius * CGFloat(sin(rightShoulderAngle.radians))
        )
        
        path.move(to: noseTip)
        path.addLine(to: rightShoulder)
        // Arc around the base to the left shoulder
        path.addArc(
            center: center,
            radius: radius,
            startAngle: rightShoulderAngle,
            endAngle: leftShoulderAngle,
            clockwise: false
        )
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
        let radius = min(w, h) * 0.35
        
        // Top forward pointy nose
        let noseTip = CGPoint(x: w / 2, y: 0)
        let leftShoulder = CGPoint(x: center.x - radius * 0.9, y: center.y - radius * 0.4)
        let rightShoulder = CGPoint(x: center.x + radius * 0.9, y: center.y - radius * 0.4)
        
        path.move(to: noseTip)
        path.addLine(to: rightShoulder)
        
        // Right SL chevron wing notch
        let rightWingOut = CGPoint(x: w * 0.98, y: center.y + radius * 0.2)
        let rightWingIn = CGPoint(
            x: center.x + radius * CGFloat(cos(Angle(degrees: 30).radians)),
            y: center.y + radius * CGFloat(sin(Angle(degrees: 30).radians))
        )
        path.addLine(to: rightWingOut)
        path.addLine(to: rightWingIn)
        
        // Bottom arc centered exactly at center of rect
        path.addArc(
            center: center,
            radius: radius,
            startAngle: Angle(degrees: 30),
            endAngle: Angle(degrees: 150),
            clockwise: false
        )
        
        // Left SL chevron wing notch
        let leftWingOut = CGPoint(x: w * 0.02, y: center.y + radius * 0.2)
        path.addLine(to: leftWingOut)
        path.addLine(to: leftShoulder)
        path.addLine(to: noseTip)
        path.closeSubpath()
        
        return path
    }
}

/// Vector shape for KIA / Dead player ("X" icon)
public struct SquadDeadXShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let strokeWidth = min(w, h) * 0.22
        let inset = min(w, h) * 0.12
        
        // Diagonal 1: Top-Left to Bottom-Right
        path.move(to: CGPoint(x: inset, y: inset + strokeWidth * 0.5))
        path.addLine(to: CGPoint(x: inset + strokeWidth * 0.5, y: inset))
        path.addLine(to: CGPoint(x: w - inset, y: h - inset - strokeWidth * 0.5))
        path.addLine(to: CGPoint(x: w - inset - strokeWidth * 0.5, y: h - inset))
        path.closeSubpath()
        
        // Diagonal 2: Top-Right to Bottom-Left
        path.move(to: CGPoint(x: w - inset, y: inset + strokeWidth * 0.5))
        path.addLine(to: CGPoint(x: w - inset - strokeWidth * 0.5, y: inset))
        path.addLine(to: CGPoint(x: inset, y: h - inset - strokeWidth * 0.5))
        path.addLine(to: CGPoint(x: inset + strokeWidth * 0.5, y: h - inset))
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
        let clampedBpm = max(min(heartRate, 220.0), 30.0)
        return 60.0 / clampedBpm
    }
    
    public var body: some View {
        ZStack {
            if heartRate > 0 {
                // Expanding pulse ring
                Circle()
                    .stroke(tintColor.opacity(isPulsing ? 0.0 : 0.8), lineWidth: 1.5)
                    .scaleEffect(isPulsing ? 1.9 : 0.8)
                
                // Solid center core dot
                Circle()
                    .fill(tintColor)
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
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
