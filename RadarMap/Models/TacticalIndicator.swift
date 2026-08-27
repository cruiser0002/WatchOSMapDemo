import Foundation
import CoreLocation

/// Category of tactical indicator
public enum TacticalIndicatorCategory: String, Codable, CaseIterable, Identifiable {
    case squadOrder = "squadOrder"
    case enemyIndicator = "enemyIndicator"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .squadOrder:
            return "Squad Orders"
        case .enemyIndicator:
            return "Enemy Indicators"
        }
    }
}

/// Specific type of indicator / order
public enum TacticalIndicatorType: String, Codable, CaseIterable, Identifiable {
    // Squad Orders
    case watchHere = "watchHere"
    case goHere = "goHere"
    case attackHere = "attackHere"
    
    // Enemy Indicators
    case infantry = "infantry"
    case lightVehicle = "lightVehicle"
    case heavyVehicle = "heavyVehicle"
    
    public var id: String { rawValue }
    
    public var category: TacticalIndicatorCategory {
        switch self {
        case .watchHere, .goHere, .attackHere:
            return .squadOrder
        case .infantry, .lightVehicle, .heavyVehicle:
            return .enemyIndicator
        }
    }
    
    public var title: String {
        switch self {
        case .watchHere:
            return "Watch"
        case .goHere:
            return "Go"
        case .attackHere:
            return "Attack"
        case .infantry:
            return "Infantry"
        case .lightVehicle:
            return "Light vehicle"
        case .heavyVehicle:
            return "Heavy vehicle"
        }
    }
}

/// Active placed tactical indicator
public struct TacticalIndicator: Identifiable, Codable, Equatable {
    public let id: String
    public let type: TacticalIndicatorType
    public var latitude: Double
    public var longitude: Double
    public let placedByMemberId: String
    public var placedByCallsign: String?
    public let timestamp: TimeInterval
    
    public var coordinate: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }
    
    public var category: TacticalIndicatorCategory {
        type.category
    }
    
    public init(
        id: String = UUID().uuidString,
        type: TacticalIndicatorType,
        coordinate: CLLocationCoordinate2D,
        placedByMemberId: String,
        placedByCallsign: String? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.type = type
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.placedByMemberId = placedByMemberId
        self.placedByCallsign = placedByCallsign
        self.timestamp = timestamp
    }
    
    /// Calculates the aging desaturation progress (0.0 = fresh radar color, 1.0 = fully faded to gray)
    /// Over 5 minutes (300 seconds)
    public func grayFadeFactor(referenceDate: Date = Date()) -> Double {
        guard category == .enemyIndicator else { return 0.0 }
        let elapsed = max(0, referenceDate.timeIntervalSince1970 - timestamp)
        let fadeDuration = AppConstants.Subscription.enemyIndicatorFadeDurationSeconds
        return min(1.0, elapsed / fadeDuration)
    }
    
    public func isFullyFaded(referenceDate: Date = Date()) -> Bool {
        return grayFadeFactor(referenceDate: referenceDate) >= 1.0
    }
}
