import SwiftUI

public struct MemberAnnotationView: View {
    public let member: SquadMember
    public let isMe: Bool
    
    public init(member: SquadMember, isMe: Bool = false) {
        self.member = member
        self.isMe = isMe
    }
    
    /// Determines whether the player is considered KIA / Downed
    private var isKIA: Bool {
        member.heartRate <= 0 || member.status == .downed
    }
    
    /// Indicator theme color based on state, self-status, or custom tactical color
    private var indicatorColor: Color {
        if isKIA {
            return .red
        }
        if isMe {
            return Color(hex: member.colorHex) ?? .green
        }
        return Color(hex: member.colorHex) ?? .green
    }
    
    public var body: some View {
        // Tactical Vector Marker (center is the exact coordinate and breathing circle center)
        ZStack {
            if isKIA {
                // KIA / Downed Marker ("X" shape)
                SquadDeadXShape()
                    .fill(Color.red)
                    .frame(width: 18, height: 18)
                    .overlay(
                        SquadDeadXShape()
                            .stroke(Color.white.opacity(0.8), lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(0.8), radius: 2)
            } else {
                // Live Squad Indicator (SL vs Teammate Player)
                if member.isHost {
                    // Squad Leader (SL) Icon
                    SquadLeaderShape()
                        .fill(indicatorColor)
                        .overlay(
                            SquadLeaderShape()
                                .stroke(isMe ? Color.white : Color.black.opacity(0.8), lineWidth: 1.2)
                        )
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(member.heading))
                        .shadow(color: .black.opacity(0.7), radius: 2)
                        .overlay(
                            // Central heart-rate pulse core
                            SquadPulseCore(heartRate: member.heartRate, tintColor: isMe ? .white : .black)
                                .frame(width: 8, height: 8)
                        )
                } else {
                    // Regular Squad Player Icon
                    SquadPlayerShape()
                        .fill(indicatorColor)
                        .overlay(
                            SquadPlayerShape()
                                .stroke(isMe ? Color.white : Color.black.opacity(0.8), lineWidth: 1.2)
                        )
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(member.heading))
                        .shadow(color: .black.opacity(0.7), radius: 2)
                        .overlay(
                            // Central heart-rate pulse core
                            SquadPulseCore(heartRate: member.heartRate, tintColor: isMe ? .white : .black)
                                .frame(width: 6, height: 6)
                        )
                }
            }
        }
        .frame(width: 26, height: 26)
        .overlay(alignment: .top) {
            // Callsign directly under the icon without altering the view center anchor
            Text(member.callsign)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(isKIA ? .red : (isMe ? .yellow : .white))
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
