import Foundation

public struct SquadRoom: Identifiable, Codable, Equatable {
    public let id: String                 // Squad Name (unique identifier)
    public var hostId: String             // Member ID of the squad creator / host
    public var maxCapacity: Int           // 4 for free tier, 12 for Pro unlock
    public var createdAt: TimeInterval
    public var lastActivityTimestamp: TimeInterval
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
        members: [String: SquadMember] = [:],
        indicators: [String: TacticalIndicator] = [:]
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.hostId = hostId
        self.maxCapacity = maxCapacity
        self.hasPin = hasPin
        self.pinHash = pinHash
        self.createdAt = createdAt
        self.lastActivityTimestamp = lastActivityTimestamp ?? createdAt
        self.members = members
        self.indicators = indicators
    }

    private enum CodingKeys: String, CodingKey {
        case id, hostId, maxCapacity, createdAt, lastActivityTimestamp, members, indicators
        case hasPin, pinHash
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hostId, forKey: .hostId)
        try container.encode(maxCapacity, forKey: .maxCapacity)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastActivityTimestamp, forKey: .lastActivityTimestamp)
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
        lastActivityTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .lastActivityTimestamp) ?? decodedCreatedAt
        hasPin = try container.decodeIfPresent(Bool.self, forKey: .hasPin) ?? false
        pinHash = try container.decodeIfPresent(String.self, forKey: .pinHash)
        members = try container.decodeIfPresent([String: SquadMember].self, forKey: .members) ?? [:]
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
