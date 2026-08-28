import SwiftUI
import MapKit

// MARK: - SquadMember Presentation Extensions

extension SquadMember {
    /// Heart rate stress level categorization color
    public var heartRateZoneColor: Color {
        switch heartRate {
        case ..<AppConstants.Health.Zones.blueMax:
            return .blue
        case AppConstants.Health.Zones.blueMax..<AppConstants.Health.Zones.greenMax:
            return .green
        case AppConstants.Health.Zones.greenMax..<AppConstants.Health.Zones.yellowMax:
            return .yellow
        case AppConstants.Health.Zones.yellowMax..<AppConstants.Health.Zones.orangeMax:
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - TacticalMapStyle Presentation Extensions

extension TacticalMapStyle {
    public var iconName: String {
        switch self {
        case .standard: return "map"
        case .radar: return "scope"
        }
    }
    
    @available(watchOS 10.0, *)
    public var mapKitStyle: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        case .radar:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }
}

// MARK: - TacticalIndicatorCategory Presentation Extensions

extension TacticalIndicatorCategory {
    public var iconName: String {
        switch self {
        case .squadOrder:
            return "star.fill"
        case .enemyIndicator:
            return "skull.fill"
        }
    }
}

// MARK: - TacticalIndicatorType Presentation Extensions

extension TacticalIndicatorType {
    /// SF Symbol descriptor
    public var iconName: String {
        switch self {
        case .watchHere:
            return "eye.fill"
        case .goHere:
            return "arrowtriangle.down"
        case .attackHere:
            return "bolt"
        case .protectHere:
            return "shield"
        case .infantry:
            return "shield.fill"
        case .lightVehicle:
            return "car.side.fill"
        case .heavyVehicle:
            return "shield.lefthalf.filled"
        }
    }
}

// MARK: - CoreLocation Extensions

#if canImport(CoreLocation)
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 1e-9 && abs(lhs.longitude - rhs.longitude) < 1e-9
    }
}
#endif
