import Foundation

public struct SquadRoom: Identifiable, Codable, Equatable {
    public let id: String                 // Squad Name (unique identifier)
    public var hostId: String             // Member ID of the squad creator / host
    public var maxCapacity: Int           // 4 for free tier, 12 for Pro unlock
    public var createdAt: TimeInterval
    public var lastActivityTimestamp: TimeInterval
    public var expireAt: TimeInterval     // TTL expiration timestamp for Firebase TTL deletion policy
    public var hasPin: Bool
    public var pinHash: String?
    public var members: [String: SquadMember] // memberId -> SquadMember
    public var indicators: [String: TacticalIndicator] // indicatorId -> TacticalIndicator
    
    public var name: String { id }
    
    public init(
        id: String,
        hostId: String,
        maxCapacity: Int = AppConstants.Subscription.freeTierMaxCapacity,
        hasPin: Bool = false,
        pinHash: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        lastActivityTimestamp: TimeInterval? = nil,
        expireAt: TimeInterval? = nil,
        members: [String: SquadMember] = [:],
        indicators: [String: TacticalIndicator] = [:]
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.hostId = hostId
        self.maxCapacity = maxCapacity
        self.hasPin = hasPin
        self.pinHash = pinHash
        self.createdAt = createdAt
        let activeTs = lastActivityTimestamp ?? createdAt
        self.lastActivityTimestamp = activeTs
        self.expireAt = expireAt ?? (activeTs + AppConstants.Timing.Inactivity.ttlDurationSeconds)
        self.members = members
        self.indicators = indicators
    }

    private enum CodingKeys: String, CodingKey {
        case id, hostId, maxCapacity, createdAt, lastActivityTimestamp, expireAt, members, indicators
        case hasPin, pinHash
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hostId, forKey: .hostId)
        try container.encode(maxCapacity, forKey: .maxCapacity)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastActivityTimestamp, forKey: .lastActivityTimestamp)
        try container.encode(expireAt, forKey: .expireAt)
        try container.encode(hasPin, forKey: .hasPin)
        try container.encodeIfPresent(pinHash, forKey: .pinHash)
        try container.encode(members, forKey: .members)
        try container.encode(indicators, forKey: .indicators)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try container.decodeIfPresent(String.self, forKey: .id) ?? "SQUAD").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        hostId = try container.decodeIfPresent(String.self, forKey: .hostId) ?? "HOST"
        maxCapacity = try container.decodeIfPresent(Int.self, forKey: .maxCapacity) ?? AppConstants.Subscription.freeTierMaxCapacity
        let decodedCreatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? Date().timeIntervalSince1970
        createdAt = decodedCreatedAt
        let decodedActivity = try container.decodeIfPresent(TimeInterval.self, forKey: .lastActivityTimestamp) ?? decodedCreatedAt
        lastActivityTimestamp = decodedActivity
        expireAt = try container.decodeIfPresent(TimeInterval.self, forKey: .expireAt)
            ?? (decodedActivity + AppConstants.Timing.Inactivity.ttlDurationSeconds)
        hasPin = try container.decodeIfPresent(Bool.self, forKey: .hasPin) ?? false
        pinHash = try container.decodeIfPresent(String.self, forKey: .pinHash)
        let rawMembers = try container.decodeIfPresent([String: SquadMember].self, forKey: .members) ?? [:]
        var sanitizedMembers: [String: SquadMember] = [:]
        for (memberKey, memberVal) in rawMembers {
            if memberVal.id != memberKey {
                let correctedMember = SquadMember(
                    id: memberKey,
                    callsign: memberVal.callsign,
                    latitude: memberVal.latitude,
                    longitude: memberVal.longitude,
                    altitude: memberVal.altitude,
                    heading: memberVal.heading,
                    heartRate: memberVal.heartRate,
                    batteryLevel: memberVal.batteryLevel,
                    lastUpdatedTimestamp: memberVal.lastUpdatedTimestamp,
                    sequenceNumber: memberVal.sequenceNumber,
                    status: memberVal.status,
                    isHost: memberVal.isHost,
                    colorHex: memberVal.colorHex
                )
                sanitizedMembers[memberKey] = correctedMember
            } else {
                sanitizedMembers[memberKey] = memberVal
            }
        }
        members = sanitizedMembers
        indicators = try container.decodeIfPresent([String: TacticalIndicator].self, forKey: .indicators) ?? [:]
    }
    
    public var memberCount: Int {
        members.count
    }
    
    public var isFull: Bool {
        members.count >= maxCapacity
    }
    
    public var isEmpty: Bool {
        members.isEmpty
    }
    
    public func isIdle(cutoffDays: Double = AppConstants.Timing.Inactivity.idleCutoffDays, asOf date: Date = Date()) -> Bool {
        let secondsThreshold = cutoffDays * AppConstants.Timing.Inactivity.secondsPerDay
        let effectiveTimestamp = lastActivityTimestamp > 0 ? lastActivityTimestamp : createdAt
        return (date.timeIntervalSince1970 - effectiveTimestamp) >= secondsThreshold
    }
}
