import Foundation
import CoreLocation
import SwiftUI

public enum MemberStatus: String, Codable {
    case active
    case downed
    case inactive
}

public struct SquadMember: Identifiable, Codable, Equatable {
    public let id: String
    public var callsign: String
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var heading: Double         // 0 - 360 degrees
    public var heartRate: Double       // BPM
    public var batteryLevel: Double    // 0.0 - 1.0
    public var lastUpdatedTimestamp: TimeInterval // Epoch time in seconds
    public var sequenceNumber: Int64   // Monotonic packet sequence counter
    public var status: MemberStatus
    public var isHost: Bool
    public var colorHex: String        // Tactical marker color
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(
        id: String = UUID().uuidString,
        callsign: String,
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        heading: Double = 0.0,
        heartRate: Double = 0.0,
        batteryLevel: Double = 1.0,
        lastUpdatedTimestamp: TimeInterval = Date().timeIntervalSince1970,
        sequenceNumber: Int64 = 0,
        status: MemberStatus = .active,
        isHost: Bool = false,
        colorHex: String = "#00FF66" // Tactical Green default
    ) {
        self.id = id
        self.callsign = callsign
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.heading = heading
        self.heartRate = heartRate
        self.batteryLevel = batteryLevel
        self.lastUpdatedTimestamp = lastUpdatedTimestamp
        self.sequenceNumber = sequenceNumber
        self.status = status
        self.isHost = isHost
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, callsign, latitude, longitude, altitude, heading, heartRate, batteryLevel, lastUpdatedTimestamp, sequenceNumber, status, isHost, colorHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        callsign = try container.decodeIfPresent(String.self, forKey: .callsign) ?? id
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0.0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0.0
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        heading = try container.decodeIfPresent(Double.self, forKey: .heading) ?? 0.0
        heartRate = try container.decodeIfPresent(Double.self, forKey: .heartRate) ?? 75.0
        batteryLevel = try container.decodeIfPresent(Double.self, forKey: .batteryLevel) ?? 1.0
        lastUpdatedTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .lastUpdatedTimestamp) ?? Date().timeIntervalSince1970
        sequenceNumber = try container.decodeIfPresent(Int64.self, forKey: .sequenceNumber) ?? 0
        status = try container.decodeIfPresent(MemberStatus.self, forKey: .status) ?? .active
        isHost = try container.decodeIfPresent(Bool.self, forKey: .isHost) ?? false
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#00FF66"
    }
    
    // Heart rate stress level categorization
    public var heartRateZoneColor: Color {
        switch heartRate {
        case ..<60:
            return .blue
        case 60..<100:
            return .green
        case 100..<140:
            return .yellow
        case 140..<175:
            return .orange
        default:
            return .red
        }
    }
}
