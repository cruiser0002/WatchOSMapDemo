import Foundation
import CoreLocation

/// Category of tactical indicator
public enum TacticalIndicatorCategory: String, Codable, CaseIterable, Identifiable {
    case squadOrder = "squadOrder"
    case enemyIndicator = "enemyIndicator"
    case environment = "environment"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .squadOrder:
            return "Team Orders"
        case .enemyIndicator:
            return "Tac Indicators"
        case .environment:
            return "Environment"
        }
    }
}

/// Specific type of indicator / order
public enum TacticalIndicatorType: String, Codable, CaseIterable, Identifiable {
    // Squad Orders
    case watchHere = "watchHere"
    case goHere = "goHere"
    case attackHere = "attackHere"
    case protectHere = "protectHere"
    case flag = "flag"
    case point1 = "point1"
    case point2 = "point2"
    case point3 = "point3"
    case point4 = "point4"
    case point5 = "point5"
    case point6 = "point6"
    case point7 = "point7"
    case point8 = "point8"
    case point9 = "point9"
    case point10 = "point10"
    
    // Enemy Indicators
    case infantry = "infantry"
    case vehicle = "vehicle"
    case armor = "armor"
    case drone = "drone"
    
    // Environment Indicators
    case water = "water"
    case hazard = "hazard"
    case fire = "fire"
    case snow = "snow"
    case closure = "closure"
    case emergency = "emergency"
    
    // Backward compatibility aliases
    public static var lightVehicle: TacticalIndicatorType { .vehicle }
    public static var heavyVehicle: TacticalIndicatorType { .armor }
    
    public var id: String { rawValue }
    
    public var category: TacticalIndicatorCategory {
        switch self {
        case .watchHere, .goHere, .attackHere, .protectHere, .flag,
             .point1, .point2, .point3, .point4, .point5,
             .point6, .point7, .point8, .point9, .point10:
            return .squadOrder
        case .infantry, .vehicle, .armor, .drone:
            return .enemyIndicator
        case .water, .hazard, .fire, .snow, .closure, .emergency:
            return .environment
        }
    }
    
    public var title: String {
        switch self {
        case .watchHere:
            return "Watch"
        case .goHere:
            return "Go"
        case .attackHere:
            return "Target"
        case .protectHere:
            return "Protect"
        case .flag:
            return "Flag"
        case .point1:
            return "1"
        case .point2:
            return "2"
        case .point3:
            return "3"
        case .point4:
            return "4"
        case .point5:
            return "5"
        case .point6:
            return "6"
        case .point7:
            return "7"
        case .point8:
            return "8"
        case .point9:
            return "9"
        case .point10:
            return "10"
        case .infantry:
            return "Personnel"
        case .vehicle:
            return "Vehicle"
        case .armor:
            return "Armor"
        case .drone:
            return "Drone"
        case .water:
            return "Water"
        case .hazard:
            return "Hazard"
        case .fire:
            return "Fire"
        case .snow:
            return "Snow"
        case .closure:
            return "Closure"
        case .emergency:
            return "Emergency"
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "vehicle", "lightVehicle":
            self = .vehicle
        case "armor", "heavyVehicle":
            self = .armor
        default:
            if let type = TacticalIndicatorType(rawValue: raw) {
                self = type
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown TacticalIndicatorType: \(raw)")
            }
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
    public let expiresAt: TimeInterval?
    
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
    
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date().timeIntervalSince1970 >= expiresAt
    }
    
    public init(
        id: String = UUID().uuidString,
        type: TacticalIndicatorType,
        coordinate: CLLocationCoordinate2D,
        placedByMemberId: String,
        placedByCallsign: String? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        expiresAt: TimeInterval? = nil
    ) {
        self.id = id
        self.type = type
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.placedByMemberId = placedByMemberId
        self.placedByCallsign = placedByCallsign
        self.timestamp = timestamp
        self.expiresAt = expiresAt
    }
    
    public var firebaseValue: [String: Any] {
        var value: [String: Any] = [
            "type": type.rawValue,
            "latitude": latitude,
            "longitude": longitude,
            "placedByMemberId": placedByMemberId,
            "timestamp": timestamp
        ]
        if let expiresAt = expiresAt {
            value["expiresAt"] = expiresAt
        }
        return value
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
