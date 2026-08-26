import Foundation
import Combine
import CryptoKit

public enum PacketRejectionReason: String, Equatable {
    case outOfOrderSequence = "Out-of-order sequence number"
    case staleTimestamp = "Stale timestamp older than latest received"
    case expiredPacket = "Packet expired (> 15s transit lag)"
}

public struct RejectionEvent: Identifiable, Equatable {
    public let id = UUID()
    public let memberId: String
    public let packetTimestamp: TimeInterval
    public let reason: PacketRejectionReason
    public let rejectedAt: Date = Date()
}

public enum FirebaseSyncError: LocalizedError, Equatable {
    case roomNotFound
    case roomFull
    case incorrectPassword
    case unauthorized
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .roomNotFound:
            return "Squad room not found"
        case .roomFull:
            return "Squad room has reached maximum capacity"
        case .incorrectPassword:
            return "Invalid Squad PIN / Password"
        case .unauthorized:
            return "Unauthorized access"
        case .networkError(let msg):
            return "Network Error: \(msg)"
        }
    }
}

public final class FirebaseSyncManager: ObservableObject {
    @Published public var activeRoom: SquadRoom?
    @Published public var isConnected: Bool = false
    @Published public var syncLatencyMs: Double = 0.0
    @Published public var totalPacketsProcessed: Int = 0
    @Published public var totalPacketsRejected: Int = 0
    @Published public var latestRejection: RejectionEvent?
    @Published public var errorMessage: String?
    
    // Database endpoint configuration
    public var databaseURL: String = "https://radarmap-8adf0-default-rtdb.firebaseio.com"
    public var authToken: String? = nil
    
    // Per-member telemetry state tracking for Late Packet Rejection
    private var memberLatestTimestamps: [String: TimeInterval] = [:]
    private var memberLatestSequences: [String: Int64] = [:]
    
    // Configurable threshold for max acceptable packet age (in seconds)
    public var maxPacketAgeSeconds: TimeInterval = 15.0
    
    private var telemetryPollingTimer: AnyCancellable?
    public var urlSession: URLSession = URLSession.shared
    
    public init() {}
    
    // MARK: - Password Hashing Utility
    
    public static func hashPassword(_ pin: String, salt: String) -> String {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let combined = "\(salt):\(trimmed)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Late Packet Rejection Engine
    
    /// Validates whether an incoming telemetry packet is fresh or should be rejected.
    /// Returns true if accepted and updates tracking state, false if rejected.
    @discardableResult
    public func validateAndProcessPacket(_ packet: TelemetryPacket) -> Bool {
        let now = Date().timeIntervalSince1970
        
        // Check 1: Excessive lag / expired packet
        if (now - packet.timestamp) > maxPacketAgeSeconds {
            recordRejection(memberId: packet.memberId, timestamp: packet.timestamp, reason: .expiredPacket)
            return false
        }
        
        // Check 2: Monotonic Sequence Number check
        if let lastSeq = memberLatestSequences[packet.memberId], packet.sequenceNumber <= lastSeq {
            recordRejection(memberId: packet.memberId, timestamp: packet.timestamp, reason: .outOfOrderSequence)
            return false
        }
        
        // Check 3: Timestamp check against latest processed timestamp for this member
        if let lastTimestamp = memberLatestTimestamps[packet.memberId], packet.timestamp <= lastTimestamp {
            recordRejection(memberId: packet.memberId, timestamp: packet.timestamp, reason: .staleTimestamp)
            return false
        }
        
        // Packet is valid and accepted! Update tracking state.
        memberLatestSequences[packet.memberId] = packet.sequenceNumber
        memberLatestTimestamps[packet.memberId] = packet.timestamp
        totalPacketsProcessed += 1
        
        // Apply telemetry update to active room member
        applyTelemetryToActiveRoom(packet)
        return true
    }
    
    private func recordRejection(memberId: String, timestamp: TimeInterval, reason: PacketRejectionReason) {
        totalPacketsRejected += 1
        let event = RejectionEvent(memberId: memberId, packetTimestamp: timestamp, reason: reason)
        self.latestRejection = event
    }
    
    private func applyTelemetryToActiveRoom(_ packet: TelemetryPacket) {
        guard var room = activeRoom else { return }
        
        var member = room.members[packet.memberId] ?? SquadMember(
            id: packet.memberId,
            callsign: packet.memberId,
            latitude: packet.latitude,
            longitude: packet.longitude,
            altitude: packet.altitude,
            heading: packet.heading,
            heartRate: packet.heartRate,
            lastUpdatedTimestamp: packet.timestamp,
            sequenceNumber: packet.sequenceNumber,
            status: packet.heartRate == 0.0 ? .downed : .active
        )
        
        member.latitude = packet.latitude
        member.longitude = packet.longitude
        member.altitude = packet.altitude
        member.heading = packet.heading
        member.heartRate = packet.heartRate
        member.lastUpdatedTimestamp = packet.timestamp
        member.sequenceNumber = packet.sequenceNumber
        
        // If heart rate is 0.0, mark status as downed (KIA)
        if packet.heartRate == 0.0 {
            member.status = .downed
        } else if member.status == .downed && packet.heartRate > 0.0 {
            member.status = .active
        }
        
        room.members[packet.memberId] = member
        if Thread.isMainThread {
            self.activeRoom = room
        } else {
            DispatchQueue.main.async {
                self.activeRoom = room
            }
        }
    }
    
    // MARK: - Telemetry Dispatch
    
    public func sendTelemetryPacket(_ packet: TelemetryPacket) {
        // Validate locally first
        validateAndProcessPacket(packet)
        
        // Broadcast over Firebase Realtime Database
        guard let url = URL(string: "\(databaseURL)/telemetry/\(packet.roomId)/\(packet.memberId).json\(authParam())") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "lat": packet.latitude,
            "lng": packet.longitude,
            "alt": packet.altitude as Any,
            "hdg": packet.heading,
            "hr": packet.heartRate,
            "seq": packet.sequenceNumber,
            "ts": packet.timestamp
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonData
        
        let startTime = Date()
        urlSession.dataTask(with: request) { [weak self] _, response, error in
            if error == nil, let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                let latency = Date().timeIntervalSince(startTime) * 1000.0
                DispatchQueue.main.async {
                    self?.syncLatencyMs = latency
                }
            }
        }.resume()
    }
    
    // MARK: - Room Management
    
    public func createRoom(_ room: SquadRoom, completion: ((Result<SquadRoom, FirebaseSyncError>) -> Void)? = nil) {
        guard let url = URL(string: "\(databaseURL)/rooms/\(room.id).json\(authParam())") else {
            let err = FirebaseSyncError.networkError("Invalid URL")
            self.errorMessage = err.localizedDescription
            completion?(.failure(err))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(room) else {
            let err = FirebaseSyncError.networkError("Serialization failure")
            self.errorMessage = err.localizedDescription
            completion?(.failure(err))
            return
        }
        request.httpBody = data
        
        urlSession.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            
            if let error = error {
                let syncError = FirebaseSyncError.networkError(error.localizedDescription)
                DispatchQueue.main.async {
                    self.errorMessage = syncError.localizedDescription
                    completion?(.failure(syncError))
                }
                return
            }
            
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let syncError = FirebaseSyncError.networkError("Server returned code \(code)")
                DispatchQueue.main.async {
                    self.errorMessage = syncError.localizedDescription
                    completion?(.failure(syncError))
                }
                return
            }
            
            DispatchQueue.main.async {
                self.activeRoom = room
                self.isConnected = true
                self.memberLatestTimestamps.removeAll()
                self.memberLatestSequences.removeAll()
                self.startTelemetryPolling(roomId: room.id)
                completion?(.success(room))
            }
        }.resume()
    }
    
    public func joinRoom(id: String, member: SquadMember, pin: String? = nil, completion: ((Result<SquadRoom, FirebaseSyncError>) -> Void)? = nil) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: "\(databaseURL)/rooms/\(cleanId).json\(authParam())") else {
            let err = FirebaseSyncError.networkError("Invalid URL")
            self.errorMessage = err.localizedDescription
            completion?(.failure(err))
            return
        }
        
        urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                let syncError = FirebaseSyncError.networkError(error.localizedDescription)
                DispatchQueue.main.async {
                    self.errorMessage = syncError.localizedDescription
                    completion?(.failure(syncError))
                }
                return
            }
            
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
                  let data = data, !data.isEmpty,
                  let jsonString = String(data: data, encoding: .utf8), jsonString != "null" else {
                DispatchQueue.main.async {
                    self.errorMessage = FirebaseSyncError.roomNotFound.localizedDescription
                    completion?(.failure(.roomNotFound))
                }
                return
            }
            
            guard var room = try? JSONDecoder().decode(SquadRoom.self, from: data) else {
                DispatchQueue.main.async {
                    self.errorMessage = FirebaseSyncError.roomNotFound.localizedDescription
                    completion?(.failure(.roomNotFound))
                }
                return
            }
            
            // Validate password if required
            if room.hasPassword {
                let inputHash = FirebaseSyncManager.hashPassword(pin ?? "", salt: cleanId)
                if inputHash != (room.passwordHash ?? "") {
                    DispatchQueue.main.async {
                        self.errorMessage = FirebaseSyncError.incorrectPassword.localizedDescription
                        completion?(.failure(.incorrectPassword))
                    }
                    return
                }
            }
            
            // Validate room capacity
            if room.members.count >= room.maxCapacity && room.members[member.id] == nil {
                DispatchQueue.main.async {
                    self.errorMessage = FirebaseSyncError.roomFull.localizedDescription
                    completion?(.failure(.roomFull))
                }
                return
            }
            
            // Publish local member to room
            self.publishMemberToFirebase(roomId: cleanId, member: member)
            room.members[member.id] = member
            
            DispatchQueue.main.async {
                self.activeRoom = room
                self.isConnected = true
                self.memberLatestTimestamps.removeAll()
                self.memberLatestSequences.removeAll()
                self.startTelemetryPolling(roomId: cleanId)
                completion?(.success(room))
            }
        }.resume()
    }
    
    public func connectToRoom(_ room: SquadRoom) {
        self.activeRoom = room
        self.isConnected = true
        self.memberLatestTimestamps.removeAll()
        self.memberLatestSequences.removeAll()
        
        // Sync full room and members from Firebase
        fetchRoomDetails(roomId: room.id)
        
        // Register local members into the room on Firebase
        for (_, member) in room.members {
            publishMemberToFirebase(roomId: room.id, member: member)
        }
        
        startTelemetryPolling(roomId: room.id)
    }
    
    public func deleteRoom(roomId: String, completion: ((Bool) -> Void)? = nil) {
        stopTelemetryPolling()
        self.activeRoom = nil
        self.isConnected = false
        self.memberLatestTimestamps.removeAll()
        self.memberLatestSequences.removeAll()
        
        // Delete room node
        if let roomUrl = URL(string: "\(databaseURL)/rooms/\(roomId).json\(authParam())") {
            var req = URLRequest(url: roomUrl)
            req.httpMethod = "DELETE"
            urlSession.dataTask(with: req).resume()
        }
        
        // Delete telemetry node
        if let telUrl = URL(string: "\(databaseURL)/telemetry/\(roomId).json\(authParam())") {
            var req = URLRequest(url: telUrl)
            req.httpMethod = "DELETE"
            urlSession.dataTask(with: req) { _, _, _ in
                DispatchQueue.main.async {
                    completion?(true)
                }
            }.resume()
        } else {
            completion?(true)
        }
    }
    
    public func removePlayerEntry(roomId: String, memberId: String, completion: ((Bool) -> Void)? = nil) {
        stopTelemetryPolling()
        self.activeRoom = nil
        self.isConnected = false
        self.memberLatestTimestamps.removeAll()
        self.memberLatestSequences.removeAll()
        
        // Delete player member entry
        if let memberUrl = URL(string: "\(databaseURL)/rooms/\(roomId)/members/\(memberId).json\(authParam())") {
            var req = URLRequest(url: memberUrl)
            req.httpMethod = "DELETE"
            urlSession.dataTask(with: req).resume()
        }
        
        // Delete player telemetry entry
        if let telUrl = URL(string: "\(databaseURL)/telemetry/\(roomId)/\(memberId).json\(authParam())") {
            var req = URLRequest(url: telUrl)
            req.httpMethod = "DELETE"
            urlSession.dataTask(with: req) { _, _, _ in
                DispatchQueue.main.async {
                    completion?(true)
                }
            }.resume()
        } else {
            completion?(true)
        }
    }
    
    public func leaveRoom(isHost: Bool = false, memberId: String? = nil) {
        guard let room = activeRoom else {
            self.activeRoom = nil
            self.isConnected = false
            stopTelemetryPolling()
            return
        }
        
        if isHost {
            deleteRoom(roomId: room.id)
        } else {
            let mId = memberId ?? ""
            if !mId.isEmpty {
                removePlayerEntry(roomId: room.id, memberId: mId)
            } else {
                deleteRoom(roomId: room.id)
            }
        }
    }
    
    public func updateMember(_ member: SquadMember) {
        guard var room = activeRoom else { return }
        room.members[member.id] = member
        self.activeRoom = room
        publishMemberToFirebase(roomId: room.id, member: member)
    }
    
    public func removeMember(id: String) {
        guard var room = activeRoom else { return }
        room.members.removeValue(forKey: id)
        memberLatestTimestamps.removeValue(forKey: id)
        memberLatestSequences.removeValue(forKey: id)
        self.activeRoom = room
    }
    
    private func publishMemberToFirebase(roomId: String, member: SquadMember) {
        guard let url = URL(string: "\(databaseURL)/rooms/\(roomId)/members/\(member.id).json\(authParam())") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "id": member.id,
            "callsign": member.callsign,
            "latitude": member.latitude,
            "longitude": member.longitude,
            "altitude": member.altitude as Any,
            "heading": member.heading,
            "heartRate": member.heartRate,
            "status": member.status.rawValue,
            "isHost": member.isHost
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = data
        urlSession.dataTask(with: request).resume()
    }
    
    public func fetchRoomDetails(roomId: String) {
        guard let url = URL(string: "\(databaseURL)/rooms/\(roomId).json\(authParam())") else { return }
        
        urlSession.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            
            // Try decoding as SquadRoom or parsing members JSON dictionary
            if let decodedRoom = try? JSONDecoder().decode(SquadRoom.self, from: data) {
                DispatchQueue.main.async {
                    if var current = self.activeRoom {
                        for (id, remoteMember) in decodedRoom.members {
                            current.members[id] = remoteMember
                        }
                        self.activeRoom = current
                    }
                }
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let membersJson = json["members"] as? [String: [String: Any]] {
                DispatchQueue.main.async {
                    if var current = self.activeRoom {
                        for (memberId, memberData) in membersJson {
                            let callsign = memberData["callsign"] as? String ?? memberId
                            let lat = memberData["latitude"] as? Double ?? 0.0
                            let lng = memberData["longitude"] as? Double ?? 0.0
                            let alt = memberData["altitude"] as? Double
                            let hdg = memberData["heading"] as? Double ?? 0.0
                            let hr = memberData["heartRate"] as? Double ?? 75.0
                            let isHost = memberData["isHost"] as? Bool ?? false
                            let statusRaw = memberData["status"] as? String ?? "active"
                            let status = MemberStatus(rawValue: statusRaw) ?? .active
                            
                            let member = SquadMember(
                                id: memberId,
                                callsign: callsign,
                                latitude: lat,
                                longitude: lng,
                                altitude: alt,
                                heading: hdg,
                                heartRate: hr,
                                status: status,
                                isHost: isHost
                            )
                            current.members[memberId] = member
                        }
                        self.activeRoom = current
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Telemetry Stream Polling / Subscription
    
    private func startTelemetryPolling(roomId: String) {
        stopTelemetryPolling()
        telemetryPollingTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchRemoteTelemetry(roomId: roomId)
            }
    }
    
    private func stopTelemetryPolling() {
        telemetryPollingTimer?.cancel()
        telemetryPollingTimer = nil
    }
    
    private func fetchRemoteTelemetry(roomId: String) {
        guard let url = URL(string: "\(databaseURL)/telemetry/\(roomId).json\(authParam())") else { return }
        
        urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
            
            for (memberId, telemetryData) in json {
                guard let lat = telemetryData["lat"] as? Double,
                      let lng = telemetryData["lng"] as? Double,
                      let hdg = telemetryData["hdg"] as? Double,
                      let hr = telemetryData["hr"] as? Double,
                      let seq = telemetryData["seq"] as? Int64,
                      let ts = telemetryData["ts"] as? TimeInterval else { continue }
                
                let alt = telemetryData["alt"] as? Double
                let packet = TelemetryPacket(
                    memberId: memberId,
                    roomId: roomId,
                    latitude: lat,
                    longitude: lng,
                    altitude: alt,
                    heading: hdg,
                    heartRate: hr,
                    timestamp: ts,
                    sequenceNumber: seq
                )
                
                DispatchQueue.main.async {
                    self.validateAndProcessPacket(packet)
                }
            }
        }.resume()
    }
    
    private func authParam() -> String {
        if let token = authToken, !token.isEmpty {
            return "?auth=\(token)"
        }
        return ""
    }
}
