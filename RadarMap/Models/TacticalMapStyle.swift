import Foundation

public enum TacticalMapStyle: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case radar = "Radar"
    
    public var id: String { rawValue }
}
