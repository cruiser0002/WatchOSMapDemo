import SwiftUI

public enum RadarColorTheme: String, CaseIterable, Identifiable, Codable {
    case red = "Red"
    case green = "Green"
    
    public var id: String { rawValue }
    
    public var color: Color {
        switch self {
        case .red: return .red
        case .green: return .green
        }
    }
}
