import SwiftUI

public struct MemberAnnotationView: View {
    public let member: SquadMember
    public let isMe: Bool
    public let radarColor: Color
    
    public init(member: SquadMember, isMe: Bool = false, radarColor: Color = .green) {
        self.member = member
        self.isMe = isMe
        self.radarColor = radarColor
    }
    
    /// Determines whether the player is considered KIA / Downed
    private var isKIA: Bool {
        member.status == .downed
    }
    
    /// Indicator theme color based on state, self-status, or radar color theme
    public var indicatorColor: Color {
        if !isMe && member.isStale {
            return .gray
        }
        return radarColor
    }
    
    public var body: some View {
        // Tactical Vector Marker (center is the exact coordinate and breathing circle center)
        ZStack {
            if isKIA {
                // KIA / Downed Marker ("X" shape) - Pre-rendered GPU Sprite
                TacticalSpriteCache.shared.deadXSprite(color: indicatorColor, size: 18)
            } else {
                // Live Squad Indicator (SL vs Teammate Player)
                if member.isHost {
                    // Squad Leader (SL) Icon (Pre-rendered Body + Hardware Heading Rotation)
                    ZStack {
                        TacticalSpriteCache.shared.leaderSprite(color: indicatorColor, size: 22)
                            .rotationEffect(.degrees(member.heading))
                        
                        // Central heart-rate pulse core (theme color for high visibility)
                        SquadPulseCore(heartRate: member.heartRate, tintColor: indicatorColor)
                            .frame(width: 6, height: 6)
                    }
                    .frame(width: 26, height: 26)
                } else {
                    // Regular Squad Player Icon (Pre-rendered Body + Hardware Heading Rotation)
                    ZStack {
                        TacticalSpriteCache.shared.playerSprite(color: indicatorColor, size: 18)
                            .rotationEffect(.degrees(member.heading))
                        
                        // Central heart-rate pulse core (theme color for high visibility)
                        SquadPulseCore(heartRate: member.heartRate, tintColor: indicatorColor)
                            .frame(width: 6, height: 6)
                    }
                    .frame(width: 26, height: 26)
                }
            }
        }
        .frame(width: 26, height: 26)
        .overlay(alignment: .top) {
            // Callsign directly under the icon without altering the view center anchor, following radar color scheme
            Text(member.callsign)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor((!isMe && member.isStale) ? .gray : radarColor)
                .lineLimit(1)
                .padding(.horizontal, 2.5)
                .padding(.vertical, 0.5)
                .background(Color.black.opacity(0.8))
                .cornerRadius(2)
                .fixedSize()
                .offset(y: 28)
        }
    }
}
