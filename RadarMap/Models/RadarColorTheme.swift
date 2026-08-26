import SwiftUI

public enum RadarColorTheme: String, CaseIterable, Identifiable, Codable {
    case green = "Green"
    case red = "Red"
    
    public var id: String { rawValue }
    
    public var color: Color {
        switch self {
        case .green: return .green
        case .red: return .red
        }
    }
}
