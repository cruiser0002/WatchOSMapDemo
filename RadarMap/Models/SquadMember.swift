import Foundation
import CoreLocation

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
    public var lastAnimationDuration: TimeInterval // Delta time between packets for translation animation (0.0s for instant stepping)
    
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
        heartRate: Double = AppConstants.Health.defaultRestingHeartRate,
        batteryLevel: Double = 1.0,
        lastUpdatedTimestamp: TimeInterval = Date().timeIntervalSince1970,
        sequenceNumber: Int64 = 0,
        status: MemberStatus = .active,
        isHost: Bool = false,
        colorHex: String = AppConstants.UI.defaultTacticalColorHex,
        lastAnimationDuration: TimeInterval = 0.0
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
        self.lastAnimationDuration = lastAnimationDuration
    }

    private enum CodingKeys: String, CodingKey {
        case id, callsign, latitude, longitude, altitude, heading, heartRate, batteryLevel, lastUpdatedTimestamp, sequenceNumber, status, isHost, colorHex
    }

    /// Serializes member metadata for the room roster endpoint (`/rooms/{roomId}/members`).
    /// Dynamic real-time telemetry (location, heading, heart rate) is purposefully excluded here
    /// and streamed independently over the telemetry endpoint (`/telemetry/{roomId}`).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(callsign, forKey: .callsign)
        try container.encode(isHost, forKey: .isHost)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        callsign = try container.decodeIfPresent(String.self, forKey: .callsign) ?? ""
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0.0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0.0
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        heading = try container.decodeIfPresent(Double.self, forKey: .heading) ?? 0.0
        heartRate = try container.decodeIfPresent(Double.self, forKey: .heartRate) ?? AppConstants.Health.defaultRestingHeartRate
        batteryLevel = try container.decodeIfPresent(Double.self, forKey: .batteryLevel) ?? AppConstants.UI.defaultBatteryLevel
        lastUpdatedTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .lastUpdatedTimestamp) ?? Date().timeIntervalSince1970
        sequenceNumber = try container.decodeIfPresent(Int64.self, forKey: .sequenceNumber) ?? 0
        status = try container.decodeIfPresent(MemberStatus.self, forKey: .status) ?? .active
        isHost = try container.decodeIfPresent(Bool.self, forKey: .isHost) ?? false
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? AppConstants.UI.defaultTacticalColorHex
        lastAnimationDuration = 0.0
    }
    
    // MARK: - Stale / Inactivity Timeout Configuration
    
    /// Stale timeout multiplier (M). The number of missed update intervals
    /// before a squad member's telemetry is considered stale and rendered gray.
    public static var staleTimeoutMultiplier: Double = AppConstants.Timing.Stale.defaultTimeoutMultiplier
    
    /// Default update interval in seconds when calculating timeout.
    public static var defaultUpdateInterval: TimeInterval = AppConstants.Timing.Stale.defaultUpdateInterval
    
    /// Calculates the stale timeout duration in seconds: M * updateInterval.
    /// E.g. If M = 15 and update interval = 2.0s, timeout is 30.0s.
    public static func staleTimeoutDuration(
        updateInterval: TimeInterval = defaultUpdateInterval,
        multiplier: Double = staleTimeoutMultiplier
    ) -> TimeInterval {
        multiplier * updateInterval
    }
    
    /// Determines whether the member's telemetry is older than the computed stale timeout (M * updateInterval).
    public func isStale(
        updateInterval: TimeInterval = SquadMember.defaultUpdateInterval,
        multiplier: Double = SquadMember.staleTimeoutMultiplier,
        asOf now: Date = Date()
    ) -> Bool {
        let timeout = SquadMember.staleTimeoutDuration(updateInterval: updateInterval, multiplier: multiplier)
        return now.timeIntervalSince1970 - lastUpdatedTimestamp > timeout
    }
    
    /// Determines whether the member's telemetry is older than the default stale timeout.
    public var isStale: Bool {
        isStale(updateInterval: SquadMember.defaultUpdateInterval, multiplier: SquadMember.staleTimeoutMultiplier, asOf: Date())
    }
    
    /// Determines whether the member's telemetry is stale relative to a reference date.
    public func isStale(asOf now: Date) -> Bool {
        isStale(updateInterval: SquadMember.defaultUpdateInterval, multiplier: SquadMember.staleTimeoutMultiplier, asOf: now)
    }
}
