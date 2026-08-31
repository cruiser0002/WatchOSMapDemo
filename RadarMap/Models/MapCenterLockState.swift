import Foundation

/// Defines whether the map center is locked to follow the local player or unlocked for free map inspection.
public enum MapCenterLockState: String, CaseIterable, Identifiable, Codable {
    case unlocked = "unlocked"
    case locked = "locked"
    
    public var id: String { rawValue }
    
    public var isLocked: Bool {
        self == .locked
    }
    
    public var isUnlocked: Bool {
        self == .unlocked
    }
    
    public var iconName: String {
        switch self {
        case .locked:
            return "location.fill"
        case .unlocked:
            return "location"
        }
    }
}
