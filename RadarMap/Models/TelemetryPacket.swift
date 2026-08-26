import Foundation

public struct TelemetryPacket: Codable, Equatable {
    public let memberId: String
    public let roomId: String
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let heading: Double
    public let heartRate: Double
    public let timestamp: TimeInterval   // Generation timestamp (seconds since epoch)
    public let sequenceNumber: Int64     // Monotonically increasing sequence number
    
    public init(
        memberId: String,
        roomId: String,
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        heading: Double,
        heartRate: Double,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        sequenceNumber: Int64
    ) {
        self.memberId = memberId
        self.roomId = roomId
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.heading = heading
        self.heartRate = heartRate
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
    }
}
