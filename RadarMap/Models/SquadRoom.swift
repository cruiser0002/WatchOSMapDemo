import Foundation

public struct SquadRoom: Identifiable, Codable, Equatable {
    public let id: String                 // Squad Name (unique identifier)
    public var hostId: String
    public var maxCapacity: Int           // 4 for free tier, 999 for Pro unlock
    public var createdAt: TimeInterval
    public var hasPassword: Bool
    public var passwordHash: String?
    public var isBluetoothAdvertising: Bool
    public var members: [String: SquadMember] // memberId -> SquadMember
    
    public var name: String { id }
    
    public init(
        id: String,
        hostId: String,
        maxCapacity: Int = 4,
        hasPassword: Bool = false,
        passwordHash: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        isBluetoothAdvertising: Bool = true,
        members: [String: SquadMember] = [:]
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.hostId = hostId
        self.maxCapacity = maxCapacity
        self.hasPassword = hasPassword
        self.passwordHash = passwordHash
        self.createdAt = createdAt
        self.isBluetoothAdvertising = isBluetoothAdvertising
        self.members = members
    }

    private enum CodingKeys: String, CodingKey {
        case id, hostId, maxCapacity, createdAt, hasPassword, passwordHash, isBluetoothAdvertising, members
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try container.decodeIfPresent(String.self, forKey: .id) ?? "SQUAD").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        hostId = try container.decodeIfPresent(String.self, forKey: .hostId) ?? "HOST"
        maxCapacity = try container.decodeIfPresent(Int.self, forKey: .maxCapacity) ?? 999
        createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? Date().timeIntervalSince1970
        hasPassword = try container.decodeIfPresent(Bool.self, forKey: .hasPassword) ?? false
        passwordHash = try container.decodeIfPresent(String.self, forKey: .passwordHash)
        isBluetoothAdvertising = try container.decodeIfPresent(Bool.self, forKey: .isBluetoothAdvertising) ?? true
        members = try container.decodeIfPresent([String: SquadMember].self, forKey: .members) ?? [:]
    }
    
    public var memberCount: Int {
        members.count
    }
    
    public var isFull: Bool {
        members.count >= maxCapacity
    }
}
