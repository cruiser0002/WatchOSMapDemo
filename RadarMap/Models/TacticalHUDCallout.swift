import Foundation

// MARK: - Tactical Guide Callout Model
public enum TacticalHUDCallout: String, CaseIterable, Identifiable {
    case config = "Configuration"
    case tacticalCommands = "Tactical Commands"
    case centerMap = "Center Map"
    case mapView = "Map View"
    case heartRate = "Heart Rate & KIA"
    
    public var id: String { rawValue }
    
    public var codeTag: String {
        switch self {
        case .config: return "SYS-CFG"
        case .tacticalCommands: return "TAC-COM"
        case .centerMap: return "NAV-POS"
        case .mapView: return "HUD-MODE"
        case .heartRate: return "BIO-STAT"
        }
    }
    
    public var iconName: String {
        switch self {
        case .config: return "gearshape.fill"
        case .tacticalCommands: return "star.fill"
        case .centerMap: return "location.fill"
        case .mapView: return "map"
        case .heartRate: return "waveform.path.ecg"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .config: return "Settings"
        case .tacticalCommands: return "Commands"
        case .centerMap: return "Center Map"
        case .mapView: return "Map View"
        case .heartRate: return "Pulse & KIA"
        }
    }
    
    public var actionInstruction: String {
        switch self {
        case .config:
            return "Tap the top-left gear icon to open squad management, change radar color themes, adjust refresh rates, and configure audio/haptics."
        case .tacticalCommands:
            return "Tap the top center star button to place tactical objective markers, rally points, enemy warnings, and broadcast squad orders."
        case .centerMap:
            return "Tap the bottom-left arrow to instantly snap the viewport back to your real-time GPS coordinate and reset zoom to default."
        case .mapView:
            return "Tap the bottom-right map icon to toggle between the high-efficiency OLED vector radar and full map tiles."
        case .heartRate:
            return "Shows live HealthKit heart rate and pulse wave. Press and HOLD the pill button for 1.2s to toggle KIA status with your squad."
        }
    }
    
    public var gestureHint: String {
        switch self {
        case .config: return "TAP ICON"
        case .tacticalCommands: return "TAP ICON"
        case .centerMap: return "TAP ICON"
        case .mapView: return "TAP ICON"
        case .heartRate: return "HOLD 1.2s"
        }
    }
}
