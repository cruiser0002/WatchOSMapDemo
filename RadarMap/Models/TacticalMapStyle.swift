import SwiftUI
import MapKit

public enum TacticalMapStyle: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case topography = "Topography"
    case satellite = "Satellite"
    case radar = "Radar"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .standard: return "map"
        case .topography: return "mountain.2"
        case .satellite: return "globe.americas.fill"
        case .radar: return "scope"
        }
    }
    
    @available(watchOS 10.0, *)
    public var mapKitStyle: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .realistic)
        case .topography:
            return .hybrid(elevation: .realistic)
        case .satellite:
            return .imagery(elevation: .realistic)
        case .radar:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }
}
