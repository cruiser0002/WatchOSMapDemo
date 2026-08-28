import Foundation
import Combine
import CryptoKit
import CoreLocation

public enum PacketRejectionReason: String, Equatable {
    case outOfOrderSequence = "Out-of-order sequence number"
    case staleTimestamp = "Stale timestamp older than latest received"
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
    case roomAlreadyExists
    case duplicateCallsign
    case emptyRoomName
    case emptyCallsign
    case roomFull
    case incorrectPin
    case incorrectPassword
    case unauthorized
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .roomNotFound:
            return "Room not found"
        case .roomAlreadyExists:
            return "Room already exists"
        case .duplicateCallsign:
            return "Callsign already taken in this room"
        case .emptyRoomName:
            return "Room name cannot be empty"
        case .emptyCallsign:
            return "Callsign cannot be empty"
        case .roomFull:
            return "Room has reached maximum capacity"
        case .incorrectPin, .incorrectPassword:
            return "Invalid PIN / Password"
        case .unauthorized:
            return "Unauthorized access"
        case .networkError(let msg):
            return "Network Error: \(msg)"
        }
    }
}

public final class FirebaseSyncManager: ObservableObject {
    @Published public var activeRoom: SquadRoom? {
        didSet {
            if oldValue?.members.count != activeRoom?.members.count {
                recalculateAdaptivePollingInterval()
            }
        }
    }

    @Published public var isConnected: Bool = false
    @Published public var syncLatencyMs: Double = 0.0
    @Published public var totalPacketsProcessed: Int = 0
    @Published public var totalPacketsRejected: Int = 0
    @Published public var latestRejection: RejectionEvent?
    @Published public var errorMessage: String?
    @Published public var squadMembersArray: [SquadMember] = []
    
    @Published public var pollingInterval: TimeInterval = AppConstants.Timing.AdaptiveRate.baselineInterval
    @Published public var isWristActive: Bool = true
    
    public let networkQualityMonitor = NetworkQualityMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    // Database endpoint configuration
    public var databaseURL: String = AppConstants.Network.defaultDatabaseURL
    public var authToken: String? = nil
    
    // Local member ID for bandwidth saving / avoiding overwriting live telemetry with server data
    public var localMemberId: String? = nil
    
    // Per-member telemetry state tracking for Late Packet Rejection
    private var memberLatestTimestamps: [String: TimeInterval] = [:]
    private var memberLatestSequences: [String: Int64] = [:]
    
    // Tactical indicators bandwidth-conserving change tracker
    public var lastKnownTacticalUpdatedAt: TimeInterval = 0.0
    
    private var telemetryPollingTimer: AnyCancellable?
    public var urlSession: URLSession = URLSession.shared
    
    // SSE packet accumulator — coalesces per-member delta events into a single batch flush
    // per runloop turn so activeRoom is only assigned once regardless of how many members
    // sent updates in the same SSE burst.
    private var ssePendingPackets: [String: TelemetryPacket] = [:]   // keyed by memberId
    private var sseFlushPending: Bool = false
    
    public init() {
        // Recalculate polling interval only when player count or connection grade changes —
        // not on every coordinate update — preventing spurious Timer restarts.
        Publishers.CombineLatest(
            $activeRoom.map { $0?.members.count ?? 0 }.removeDuplicates(),
            networkQualityMonitor.$connectionGrade
        )
        .sink { [weak self] _, _ in
            self?.recalculateAdaptivePollingInterval()
        }
        .store(in: &cancellables)
        
        // Rebuild squadMembersArray only when member count changes (same guard as above).
        $activeRoom
            .map { $0.map { Array($0.members.values) } ?? [] }
            .removeDuplicates { $0.count == $1.count && zip($0, $1).allSatisfy { $0.id == $1.id } }
            .assign(to: &$squadMembersArray)
    }
    
    // MARK: - Constant Bandwidth Rate Adaptation
    
    /// The maximum number of concurrent players supported at peak 1.0 Hz before throttling
    /// is engaged to keep theoretical aggregate bandwidth constant.
    public static let constantBandwidthPlayerThreshold: Int = AppConstants.Timing.ConstantBandwidth.playerThreshold
    
    /// The baseline maximum update frequency (in Hz).
    public static let baselineMaxUpdateRateHz: Double = AppConstants.Timing.ConstantBandwidth.baselineMaxUpdateRateHz
    
    /// Solves for the maximum update rate (in Hz) given the active player count,
    /// ensuring aggregate theoretical bandwidth stays constant beyond `playerThreshold`.
    ///
    /// Equation:
    ///   R_max(P) = R_base * min(1.0, N_threshold / max(1, P))
    ///
    /// - Parameters:
    ///   - playerCount: Active number of players on the server.
    ///   - playerThreshold: Player count threshold N (defaults to `constantBandwidthPlayerThreshold` = 10).
    ///   - baselineRateHz: Baseline peak update rate in Hz (defaults to `baselineMaxUpdateRateHz` = 1.0).
    /// - Returns: The maximum update rate in Hertz (updates / second).
    public static func solveMaxUpdateRateHz(
        playerCount: Int,
        playerThreshold: Int = constantBandwidthPlayerThreshold,
        baselineRateHz: Double = baselineMaxUpdateRateHz
    ) -> Double {
        guard playerCount > 0 else { return baselineRateHz }
        if playerCount <= playerThreshold {
            return baselineRateHz
        }
        return baselineRateHz * (Double(playerThreshold) / Double(playerCount))
    }
    
    /// Solves for the update interval (in seconds) corresponding to `solveMaxUpdateRateHz`.
    ///
    /// - Parameters:
    ///   - playerCount: Active number of players on the server.
    ///   - playerThreshold: Player count threshold N (defaults to `constantBandwidthPlayerThreshold` = 10).
    ///   - baselineRateHz: Baseline peak update rate in Hz (defaults to `baselineMaxUpdateRateHz` = 1.0).
    /// - Returns: The time interval between updates in seconds.
    public static func solveUpdateInterval(
        playerCount: Int,
        playerThreshold: Int = constantBandwidthPlayerThreshold,
        baselineRateHz: Double = baselineMaxUpdateRateHz
    ) -> TimeInterval {
        let rateHz = solveMaxUpdateRateHz(
            playerCount: playerCount,
            playerThreshold: playerThreshold,
            baselineRateHz: baselineRateHz
        )
        guard rateHz > 0 else { return 1.0 / baselineRateHz }
        return 1.0 / rateHz
    }
    
    // MARK: - PIN / Password Hashing Utility
    
    public static func hashPin(_ pin: String, salt: String) -> String {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let combined = "\(salt):\(trimmed)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    public static func hashPassword(_ pin: String, salt: String) -> String {
        return hashPin(pin, salt: salt)
    }
    
    // MARK: - Late Packet Rejection Engine
    
    /// Checks packet freshness and updates sequence / timestamp tracking.
    /// Returns true if valid, false if rejected.
    private func checkAndTrackPacketFreshness(_ packet: TelemetryPacket) -> Bool {
        // Check 1: Monotonic Sequence Number check (when present)
        if packet.sequenceNumber > 0, let lastSeq = memberLatestSequences[packet.memberId], lastSeq > 0, packet.sequenceNumber <= lastSeq {
            recordRejection(memberId: packet.memberId, timestamp: packet.timestamp, reason: .outOfOrderSequence)
            return false
        }
        
        // Check 2: Timestamp check against latest processed timestamp for this member
        if let lastTimestamp = memberLatestTimestamps[packet.memberId], packet.timestamp <= lastTimestamp {
            recordRejection(memberId: packet.memberId, timestamp: packet.timestamp, reason: .staleTimestamp)
            return false
        }
        
        // Packet is valid and accepted! Update tracking state.
        if packet.sequenceNumber > 0 {
            memberLatestSequences[packet.memberId] = packet.sequenceNumber
        }
        memberLatestTimestamps[packet.memberId] = packet.timestamp
        return true
    }
    
    /// Validates whether an incoming telemetry packet is fresh or should be rejected.
    /// Returns true if accepted and updates tracking state, false if rejected.
    @discardableResult
    public func validateAndProcessPacket(_ packet: TelemetryPacket) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.validateAndProcessPacket(packet)
            }
            return true
        }
        
        guard checkAndTrackPacketFreshness(packet) else { return false }
        totalPacketsProcessed += 1
        
        // Apply telemetry update to active room member
        applyTelemetryToActiveRoom(packet)
        return true
    }
    
    /// Validates and applies a batch of telemetry packets, updating activeRoom in a single
    /// pass to avoid redundant @Published view re-evaluations.
    @discardableResult
    public func validateAndProcessPackets(_ packets: [TelemetryPacket]) -> Int {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.validateAndProcessPackets(packets)
            }
            return 0
        }
        
        guard var room = activeRoom, !packets.isEmpty else { return 0 }
        var acceptedCount = 0
        
        for packet in packets {
            if checkAndTrackPacketFreshness(packet) {
                acceptedCount += 1
                updateMember(with: packet, in: &room.members)
            }
        }
        
        guard acceptedCount > 0 else { return 0 }
        
        self.totalPacketsProcessed += acceptedCount
        self.activeRoom = room
        return acceptedCount
    }
    
    private func recordRejection(memberId: String, timestamp: TimeInterval, reason: PacketRejectionReason) {
        let event = RejectionEvent(memberId: memberId, packetTimestamp: timestamp, reason: reason)
        if Thread.isMainThread {
            totalPacketsRejected += 1
            self.latestRejection = event
        } else {
            DispatchQueue.main.async {
                self.totalPacketsRejected += 1
                self.latestRejection = event
            }
        }
    }
    
    /// Calculates the forward geodesic bearing / Course Over Ground (in degrees 0 - 360) from coordinate 1 to coordinate 2.
    public static func calculateBearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * AppConstants.Location.degreesToRadiansFactor
        let lon1 = start.longitude * AppConstants.Location.degreesToRadiansFactor
        let lat2 = end.latitude * AppConstants.Location.degreesToRadiansFactor
        let lon2 = end.longitude * AppConstants.Location.degreesToRadiansFactor
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        
        let degrees = radiansBearing * AppConstants.Location.radiansToDegreesFactor
        return (degrees + AppConstants.Location.fullCircleDegrees).truncatingRemainder(dividingBy: AppConstants.Location.fullCircleDegrees)
    }
    
    private func updateMember(with packet: TelemetryPacket, in members: inout [String: SquadMember]) {
        let isExistingMember = members[packet.memberId] != nil
        var member = members[packet.memberId] ?? SquadMember(
            id: packet.memberId,
            callsign: packet.memberId,
            latitude: packet.latitude,
            longitude: packet.longitude,
            altitude: packet.altitude,
            heading: packet.heading,
            heartRate: packet.heartRate,
            lastUpdatedTimestamp: packet.timestamp,
            sequenceNumber: packet.sequenceNumber,
            status: packet.heartRate == AppConstants.Health.flatlineHeartRate ? .downed : .active
        )
        
        // Compute Course Over Ground (COG) if player moved > threshold
        if isExistingMember {
            let prevCoord = CLLocationCoordinate2D(latitude: member.latitude, longitude: member.longitude)
            let newCoord = CLLocationCoordinate2D(latitude: packet.latitude, longitude: packet.longitude)
            let prevLoc = CLLocation(latitude: member.latitude, longitude: member.longitude)
            let newLoc = CLLocation(latitude: packet.latitude, longitude: packet.longitude)
            let distanceMoved = prevLoc.distance(from: newLoc)
            let isInitialPlaceholder = (abs(member.latitude) < 1e-5 && abs(member.longitude) < 1e-5)
            
            if packet.heading > 0.0 {
                member.heading = packet.heading
            } else if !isInitialPlaceholder && distanceMoved > AppConstants.Location.minDisplacementForCourseOverGroundMeters {
                let cogHeading = FirebaseSyncManager.calculateBearing(from: prevCoord, to: newCoord)
                member.heading = cogHeading
            }
            // If distanceMoved <= threshold and packet.heading == 0, retain previous heading
        } else if packet.heading > 0.0 {
            member.heading = packet.heading
        }
        
        member.latitude = packet.latitude
        member.longitude = packet.longitude
        member.altitude = packet.altitude
        member.heartRate = packet.heartRate
        member.lastUpdatedTimestamp = packet.timestamp
        member.sequenceNumber = packet.sequenceNumber
        
        // If heart rate is flatline (0.0), mark status as downed (KIA)
        if packet.heartRate == AppConstants.Health.flatlineHeartRate {
            member.status = .downed
        } else if member.status == .downed && packet.heartRate > AppConstants.Health.flatlineHeartRate {
            member.status = .active
        }
        
        members[packet.memberId] = member
        
        // Feed into DeadReckoningEngine for 60 FPS smooth coordinate gliding & spring rotation
        DeadReckoningEngine.shared.updateRemotePlayer(
            id: member.id,
            newCoordinate: member.coordinate,
            newHeading: member.heading,
            packetTimestamp: packet.timestamp
        )
    }
    
    private func applyTelemetryToActiveRoom(_ packet: TelemetryPacket) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyTelemetryToActiveRoom(packet)
            }
            return
        }
        guard var room = activeRoom else { return }
        updateMember(with: packet, in: &room.members)
        self.activeRoom = room
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
        
        let payload = packet.toCompactArray()
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonData
        
        let startTime = Date()
        urlSession.dataTask(with: request) { [weak self] _, response, error in
            if error == nil, let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                let latency = Date().timeIntervalSince(startTime) * AppConstants.Timing.millisecondsPerSecond
                DispatchQueue.main.async {
                    self?.syncLatencyMs = latency
                    self?.networkQualityMonitor.recordLatencySample(latency)
                }
            }
        }.resume()
    }
    
    // MARK: - Room Management
    
    public func createRoom(_ room: SquadRoom, completion: ((Result<SquadRoom, FirebaseSyncError>) -> Void)? = nil) {
        let cleanId = room.id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanId.isEmpty {
            let err = FirebaseSyncError.emptyRoomName
            DispatchQueue.main.async {
                self.errorMessage = err.localizedDescription
                completion?(.failure(err))
            }
            return
        }
        
        // Validate all member callsigns in room
        for (_, member) in room.members {
            let cleanCallsign = member.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanCallsign.isEmpty {
                let err = FirebaseSyncError.emptyCallsign
                DispatchQueue.main.async {
                    self.errorMessage = err.localizedDescription
                    completion?(.failure(err))
                }
                return
            }
        }
        
        // Validate callsign uniqueness within the room (only within this room)
        var seenCallsigns = Set<String>()
        for member in room.members.values {
            let callsignUpper = member.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if seenCallsigns.contains(callsignUpper) {
                let err = FirebaseSyncError.duplicateCallsign
                DispatchQueue.main.async {
                    self.errorMessage = err.localizedDescription
                    completion?(.failure(err))
                }
                return
            }
            seenCallsigns.insert(callsignUpper)
        }
        
        guard let url = URL(string: "\(databaseURL)/rooms/\(cleanId).json\(authParam())") else {
            let err = FirebaseSyncError.networkError("Invalid URL")
            DispatchQueue.main.async {
                self.errorMessage = err.localizedDescription
                completion?(.failure(err))
            }
            return
        }
        
        // 1. Check if room already exists on server
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
            
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
               let data = data, !data.isEmpty,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let existingId = json["id"] as? String, !existingId.isEmpty {
                // Room exists already
                let err = FirebaseSyncError.roomAlreadyExists
                DispatchQueue.main.async {
                    self.errorMessage = err.localizedDescription
                    completion?(.failure(err))
                }
                return
            }
            
            // 2. Room does not exist -> Purge old telemetry and tactical data for this room ID, then proceed with creation (PUT)
            let purgeGroup = DispatchGroup()
            
            if let telUrl = URL(string: "\(self.databaseURL)/telemetry/\(cleanId).json\(self.authParam())") {
                var delTelReq = URLRequest(url: telUrl)
                delTelReq.httpMethod = "DELETE"
                purgeGroup.enter()
                self.urlSession.dataTask(with: delTelReq) { _, _, _ in
                    purgeGroup.leave()
                }.resume()
            }
            
            if let tactUrl = URL(string: "\(self.databaseURL)/tactical/\(cleanId).json\(self.authParam())") {
                var delTactReq = URLRequest(url: tactUrl)
                delTactReq.httpMethod = "DELETE"
                purgeGroup.enter()
                self.urlSession.dataTask(with: delTactReq) { _, _, _ in
                    purgeGroup.leave()
                }.resume()
            }
            
            purgeGroup.notify(queue: .global()) {
                // Initialize clean single-field TTL metadata for telemetry & tactical subrooms
                let telTtlPayload: [String: Any] = ["expireAt": room.expireAt]
                let tactTtlPayload: [String: Any] = ["updatedAt": room.createdAt, "expireAt": room.expireAt]
                
                if let telData = try? JSONSerialization.data(withJSONObject: telTtlPayload),
                   let telUrl = URL(string: "\(self.databaseURL)/telemetry/\(cleanId).json\(self.authParam())") {
                    var putTelReq = URLRequest(url: telUrl)
                    putTelReq.httpMethod = "PUT"
                    putTelReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    putTelReq.httpBody = telData
                    self.urlSession.dataTask(with: putTelReq).resume()
                }
                
                if let tactData = try? JSONSerialization.data(withJSONObject: tactTtlPayload),
                   let tactUrl = URL(string: "\(self.databaseURL)/tactical/\(cleanId).json\(self.authParam())") {
                    var putTactReq = URLRequest(url: tactUrl)
                    putTactReq.httpMethod = "PUT"
                    putTactReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    putTactReq.httpBody = tactData
                    self.urlSession.dataTask(with: putTactReq).resume()
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let encoder = JSONEncoder()
                guard let payload = try? encoder.encode(room) else {
                    let err = FirebaseSyncError.networkError("Serialization failure")
                    DispatchQueue.main.async {
                        self.errorMessage = err.localizedDescription
                        completion?(.failure(err))
                    }
                    return
                }
                request.httpBody = payload
                
                self.urlSession.dataTask(with: request) { [weak self] _, response, error in
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
                        self.lastKnownTacticalUpdatedAt = 0.0
                        DeadReckoningEngine.shared.clearRemoteMembers()
                        self.startTelemetryPolling(roomId: room.id)
                        completion?(.success(room))
                    }
                }.resume()
            }
        }.resume()
    }
    
    public func joinRoom(id: String, member: SquadMember, pin: String? = nil, completion: ((Result<SquadRoom, FirebaseSyncError>) -> Void)? = nil) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanId.isEmpty {
            let err = FirebaseSyncError.emptyRoomName
            DispatchQueue.main.async {
                self.errorMessage = err.localizedDescription
                completion?(.failure(err))
            }
            return
        }
        
        let cleanCallsign = member.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanCallsign.isEmpty {
            let err = FirebaseSyncError.emptyCallsign
            DispatchQueue.main.async {
                self.errorMessage = err.localizedDescription
                completion?(.failure(err))
            }
            return
        }
        
        guard let url = URL(string: "\(databaseURL)/rooms/\(cleanId).json\(authParam())") else {
            let err = FirebaseSyncError.networkError("Invalid URL")
            DispatchQueue.main.async {
                self.errorMessage = err.localizedDescription
                completion?(.failure(err))
            }
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
            
            // Validate Callsign duplication (case-insensitive check against other members in this room only)
            let trimmedCallsign = member.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let callsignConflict = room.members.values.contains { existing in
                existing.id != member.id && existing.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == trimmedCallsign
            }
            if callsignConflict {
                DispatchQueue.main.async {
                    self.errorMessage = FirebaseSyncError.duplicateCallsign.localizedDescription
                    completion?(.failure(.duplicateCallsign))
                }
                return
            }
            
            // Validate PIN if required
            if room.hasPin {
                let inputHash = FirebaseSyncManager.hashPin(pin ?? "", salt: cleanId)
                let expectedHash = room.pinHash ?? ""
                if inputHash != expectedHash {
                    DispatchQueue.main.async {
                        self.errorMessage = FirebaseSyncError.incorrectPin.localizedDescription
                        completion?(.failure(.incorrectPin))
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
                self.lastKnownTacticalUpdatedAt = 0.0
                DeadReckoningEngine.shared.clearRemoteMembers()
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
        self.lastKnownTacticalUpdatedAt = 0.0
        DeadReckoningEngine.shared.clearRemoteMembers()
        
        // Sync full room and members from Firebase
        fetchRoomDetails(roomId: room.id)
        
        // Register local members into the room on Firebase
        for (_, member) in room.members {
            publishMemberToFirebase(roomId: room.id, member: member)
        }
        
        startTelemetryPolling(roomId: room.id)
    }
    
    /// Purges all local room tracking state, timestamps, tactical indicator metadata, and remote dead-reckoning players.
    public func resetLocalSessionAndIcons() {
        stopTelemetryPolling()
        self.activeRoom = nil
        self.isConnected = false
        self.memberLatestTimestamps.removeAll()
        self.memberLatestSequences.removeAll()
        self.lastKnownTacticalUpdatedAt = 0.0
        DeadReckoningEngine.shared.clearRemoteMembers()
    }
    
    public func disbandRoom(roomId: String, completion: ((Bool) -> Void)? = nil) {
        deleteRoom(roomId: roomId, completion: completion)
    }
    
    public func deleteRoom(roomId: String, completion: ((Bool) -> Void)? = nil) {
        stopTelemetryPolling()
        
        let group = DispatchGroup()
        
        // Delete room node
        if let roomUrl = URL(string: "\(databaseURL)/rooms/\(roomId).json\(authParam())") {
            var req = URLRequest(url: roomUrl)
            req.httpMethod = "DELETE"
            group.enter()
            urlSession.dataTask(with: req) { _, _, _ in
                group.leave()
            }.resume()
        }
        
        // Delete telemetry node
        if let telUrl = URL(string: "\(databaseURL)/telemetry/\(roomId).json\(authParam())") {
            var req = URLRequest(url: telUrl)
            req.httpMethod = "DELETE"
            group.enter()
            urlSession.dataTask(with: req) { _, _, _ in
                group.leave()
            }.resume()
        }
        
        // Delete tactical indicators node
        if let tactUrl = URL(string: "\(databaseURL)/tactical/\(roomId).json\(authParam())") {
            var req = URLRequest(url: tactUrl)
            req.httpMethod = "DELETE"
            group.enter()
            urlSession.dataTask(with: req) { _, _, _ in
                group.leave()
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.resetLocalSessionAndIcons()
            completion?(true)
        }
    }
    
    public func logoutPlayer(roomId: String, memberId: String, completion: ((Bool) -> Void)? = nil) {
        stopTelemetryPolling()
        
        let group = DispatchGroup()
        
        // 1. Delete player member entry
        if let memberUrl = URL(string: "\(databaseURL)/rooms/\(roomId)/members/\(memberId).json\(authParam())") {
            var req = URLRequest(url: memberUrl)
            req.httpMethod = "DELETE"
            group.enter()
            urlSession.dataTask(with: req) { _, _, _ in
                group.leave()
            }.resume()
        }
        
        // 2. Delete player telemetry entry
        if let telUrl = URL(string: "\(databaseURL)/telemetry/\(roomId)/\(memberId).json\(authParam())") {
            var req = URLRequest(url: telUrl)
            req.httpMethod = "DELETE"
            group.enter()
            urlSession.dataTask(with: req) { _, _, _ in
                group.leave()
            }.resume()
        }
        
        // 3. Delete player squad order icons from tactical node
        if let tactUrl = URL(string: "\(databaseURL)/tactical/\(roomId).json\(authParam())") {
            group.enter()
            var getReq = URLRequest(url: tactUrl)
            getReq.httpMethod = "GET"
            urlSession.dataTask(with: getReq) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
                
                var deletedAny = false
                for (indicatorId, indDict) in json {
                    if indicatorId == "updatedAt" || indicatorId == "expireAt" || indicatorId == "createdAt" || indicatorId == "lastActivityTimestamp" || indicatorId == "ttl" || indicatorId.starts(with: "_") { continue }
                    let placedBy = indDict["placedByMemberId"] as? String
                    let typeStr = indDict["type"] as? String ?? ""
                    let categoryStr = indDict["category"] as? String ?? ""
                    
                    let isSquadOrder = categoryStr == "squadOrder" ||
                                       typeStr == "watchHere" ||
                                       typeStr == "goHere" ||
                                       typeStr == "attackHere" ||
                                       typeStr == "protectHere"
                    
                    if placedBy == memberId && isSquadOrder {
                        deletedAny = true
                        if let delUrl = URL(string: "\(self?.databaseURL ?? "")/tactical/\(roomId)/\(indicatorId).json\(self?.authParam() ?? "")") {
                            var delReq = URLRequest(url: delUrl)
                            delReq.httpMethod = "DELETE"
                            group.enter()
                            self?.urlSession.dataTask(with: delReq) { _, _, _ in
                                group.leave()
                            }.resume()
                        }
                    }
                }
                
                if deletedAny {
                    self?.touchTacticalUpdatedAt(roomId: roomId)
                }
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.resetLocalSessionAndIcons()
            completion?(true)
        }
    }
    
    public func removePlayerEntry(roomId: String, memberId: String, completion: ((Bool) -> Void)? = nil) {
        logoutPlayer(roomId: roomId, memberId: memberId, completion: completion)
    }
    
    public func touchRoomActivity(roomId: String) {
        let now = Date().timeIntervalSince1970
        guard let url = URL(string: "\(databaseURL)/rooms/\(roomId)/lastActivityTimestamp.json\(authParam())") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: now) else { return }
        request.httpBody = data
        urlSession.dataTask(with: request).resume()
    }
    
    public func leaveRoom(isHost: Bool = false, memberId: String? = nil) {
        guard let room = activeRoom else {
            self.activeRoom = nil
            self.isConnected = false
            stopTelemetryPolling()
            return
        }
        
        if isHost {
            disbandRoom(roomId: room.id)
        } else {
            let mId = memberId ?? ""
            if !mId.isEmpty {
                logoutPlayer(roomId: room.id, memberId: mId)
            } else {
                stopTelemetryPolling()
                self.activeRoom = nil
                self.isConnected = false
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
        DeadReckoningEngine.shared.removePlayer(id: id)
    }
    
    private func publishMemberToFirebase(roomId: String, member: SquadMember) {
        guard let url = URL(string: "\(databaseURL)/rooms/\(roomId)/members/\(member.id).json\(authParam())") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "id": member.id,
            "callsign": member.callsign,
            "isHost": member.isHost
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = data
        urlSession.dataTask(with: request).resume()
    }
    
    public func addOrUpdateIndicator(roomId: String, indicator: TacticalIndicator) {
        guard var room = activeRoom, room.id == roomId else { return }
        room.indicators[indicator.id] = indicator
        self.activeRoom = room
        publishIndicatorToFirebase(roomId: roomId, indicator: indicator)
    }
    
    public func removeIndicator(roomId: String, indicatorId: String) {
        guard var room = activeRoom, room.id == roomId else { return }
        room.indicators.removeValue(forKey: indicatorId)
        self.activeRoom = room
        deleteIndicatorFromFirebase(roomId: roomId, indicatorId: indicatorId)
    }
    
    private func publishIndicatorToFirebase(roomId: String, indicator: TacticalIndicator) {
        guard let url = URL(string: "\(databaseURL)/tactical/\(roomId)/\(indicator.id).json\(authParam())") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let data = try? JSONEncoder().encode(indicator) else { return }
        request.httpBody = data
        urlSession.dataTask(with: request).resume()
        touchTacticalUpdatedAt(roomId: roomId)
    }
    
    private func deleteIndicatorFromFirebase(roomId: String, indicatorId: String) {
        guard let url = URL(string: "\(databaseURL)/tactical/\(roomId)/\(indicatorId).json\(authParam())") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        urlSession.dataTask(with: request).resume()
        touchTacticalUpdatedAt(roomId: roomId)
    }
    
    public func touchTacticalUpdatedAt(roomId: String) {
        let now = Date().timeIntervalSince1970
        self.lastKnownTacticalUpdatedAt = now
        guard let url = URL(string: "\(databaseURL)/tactical/\(roomId)/updatedAt.json\(authParam())") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONEncoder().encode(now) else { return }
        request.httpBody = data
        urlSession.dataTask(with: request).resume()
    }
    
    /// Bandwidth-conserving check: queries updatedAt first. Only downloads the full indicator payload when a change is detected.
    public func fetchTacticalIndicatorsIfChanged(roomId: String, force: Bool = false) {
        guard let updateUrl = URL(string: "\(databaseURL)/tactical/\(roomId)/updatedAt.json\(authParam())") else { return }
        
        urlSession.dataTask(with: updateUrl) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            let remoteUpdatedAt = (try? JSONSerialization.jsonObject(with: data) as? Double) ?? (try? JSONDecoder().decode(Double.self, from: data)) ?? 0.0
            
            if force || (remoteUpdatedAt > self.lastKnownTacticalUpdatedAt && remoteUpdatedAt > 0) {
                self.fetchFullTacticalCollection(roomId: roomId, remoteUpdatedAt: remoteUpdatedAt)
            }
        }.resume()
    }
    
    private func fetchFullTacticalCollection(roomId: String, remoteUpdatedAt: Double) {
        guard let url = URL(string: "\(databaseURL)/tactical/\(roomId).json\(authParam())") else { return }
        
        urlSession.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    if var current = self.activeRoom {
                        current.indicators = [:]
                        self.activeRoom = current
                    }
                    self.lastKnownTacticalUpdatedAt = max(self.lastKnownTacticalUpdatedAt, remoteUpdatedAt)
                }
                return
            }
            
            let metadataKeys: Set<String> = ["createdAt", "expireAt", "lastActivityTimestamp", "ttl", "updatedAt"]
            var decodedIndicators: [String: TacticalIndicator] = [:]
            for (key, val) in json {
                if key.starts(with: "_") || metadataKeys.contains(key) { continue }
                if let dict = val as? [String: Any],
                   let indData = try? JSONSerialization.data(withJSONObject: dict),
                   let ind = try? JSONDecoder().decode(TacticalIndicator.self, from: indData) {
                    decodedIndicators[ind.id] = ind
                }
            }
            
            DispatchQueue.main.async {
                if var current = self.activeRoom {
                    current.indicators = decodedIndicators
                    self.activeRoom = current
                }
                self.lastKnownTacticalUpdatedAt = max(self.lastKnownTacticalUpdatedAt, remoteUpdatedAt)
            }
        }.resume()
    }
    
    public func fetchRoomDetails(roomId: String) {
        // Fetch tactical indicators if changed or first load
        fetchTacticalIndicatorsIfChanged(roomId: roomId, force: true)
        
        guard let url = URL(string: "\(databaseURL)/rooms/\(roomId).json\(authParam())") else { return }
        
        urlSession.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            
            // Try decoding as SquadRoom or parsing members JSON dictionary
            if let decodedRoom = try? JSONDecoder().decode(SquadRoom.self, from: data) {
                DispatchQueue.main.async {
                    if var current = self.activeRoom {
                        for (id, remoteMember) in decodedRoom.members {
                            if var existing = current.members[id] {
                                existing.callsign = remoteMember.callsign
                                existing.isHost = remoteMember.isHost
                                current.members[id] = existing
                            } else {
                                current.members[id] = remoteMember
                            }
                        }
                        if !decodedRoom.indicators.isEmpty {
                            current.indicators = decodedRoom.indicators
                        }
                        self.activeRoom = current
                    }
                }
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async {
                    if var current = self.activeRoom {
                        if let membersJson = json["members"] as? [String: [String: Any]] {
                            for (memberId, memberData) in membersJson {
                                let callsign = memberData["callsign"] as? String ?? memberId
                                let isHost = memberData["isHost"] as? Bool ?? false
                                
                                if var existing = current.members[memberId] {
                                    existing.callsign = callsign
                                    existing.isHost = isHost
                                    current.members[memberId] = existing
                                } else {
                                    let member = SquadMember(
                                        id: memberId,
                                        callsign: callsign,
                                        latitude: 0.0,
                                        longitude: 0.0,
                                        isHost: isHost
                                    )
                                    current.members[memberId] = member
                                }
                            }
                        }
                        self.activeRoom = current
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Telemetry Stream Polling / Subscription
    
    public func recalculateAdaptivePollingInterval() {
        guard isWristActive else {
            let newInterval = AppConstants.Timing.AdaptiveRate.wristDownPollingInterval
            if abs(self.pollingInterval - newInterval) > AppConstants.Timing.AdaptiveRate.intervalChangeEpsilon {
                self.pollingInterval = newInterval
                if let roomId = activeRoom?.id, telemetryPollingTimer != nil {
                    startTelemetryPolling(roomId: roomId)
                }
            }
            return
        }
        
        let memberCount = activeRoom?.members.count ?? 0
        let grade = networkQualityMonitor.connectionGrade
        
        // Active rate calculated from constant bandwidth player equation: R_max(P) = R_base * min(1.0, N_threshold / P)
        let calculatedInterval = FirebaseSyncManager.solveUpdateInterval(playerCount: memberCount)
        
        let newInterval: TimeInterval
        if grade == .critical || grade == .offline {
            newInterval = max(AppConstants.Timing.AdaptiveRate.criticalInterval, calculatedInterval)
        } else if grade == .poor {
            newInterval = max(AppConstants.Timing.AdaptiveRate.poorInterval, calculatedInterval)
        } else {
            newInterval = calculatedInterval
        }
        
        if abs(self.pollingInterval - newInterval) > AppConstants.Timing.AdaptiveRate.intervalChangeEpsilon {
            self.pollingInterval = newInterval
            if let roomId = activeRoom?.id, telemetryPollingTimer != nil {
                startTelemetryPolling(roomId: roomId)
            }
        }
    }
    
    /// Updates wrist viewing activity and triggers an Instant Wake Burst upon wrist raise.
    public func setWristActive(_ active: Bool) {
        let wasActive = isWristActive
        self.isWristActive = active
        recalculateAdaptivePollingInterval()
        
        // Instant Wake Burst: When wrist is raised, immediately fetch telemetry to eliminate visual lag
        if active && (!wasActive || telemetryPollingTimer == nil), let roomId = activeRoom?.id {
            fetchRemoteTelemetry(roomId: roomId)
        }
    }
    
    /// Explicit awake trigger for gestures (e.g. double tap, screen tap, digital crown rotation)
    public func triggerWakeBurst() {
        setWristActive(true)
        if let roomId = activeRoom?.id {
            fetchRemoteTelemetry(roomId: roomId)
        }
    }
    
    public func startTelemetryPolling(roomId: String) {
        stopTelemetryPolling()
        let interval = max(AppConstants.Timing.AdaptiveRate.minimumInterval, pollingInterval)
        telemetryPollingTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchRemoteTelemetry(roomId: roomId)
            }
    }
    
    public func stopTelemetryPolling() {
        telemetryPollingTimer?.cancel()
        telemetryPollingTimer = nil
    }
    
    /// Helper to parse a TelemetryPacket from compact array format or JSON dictionary
    public static func parseTelemetryPacket(memberId: String, roomId: String, rawValue: Any) -> TelemetryPacket? {
        if let array = rawValue as? [Any] {
            return TelemetryPacket.fromCompactArray(memberId: memberId, roomId: roomId, array: array)
        } else if let telemetryData = rawValue as? [String: Any] {
            guard let lat = telemetryData["lat"] as? Double,
                  let lng = telemetryData["lng"] as? Double,
                  let hdg = telemetryData["hdg"] as? Double,
                  let hr = telemetryData["hr"] as? Double,
                  let seq = (telemetryData["seq"] as? NSNumber)?.int64Value ?? (telemetryData["seq"] as? Int64),
                  let ts = telemetryData["ts"] as? TimeInterval else { return nil }
            
            let alt = telemetryData["alt"] as? Double
            return TelemetryPacket(
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
        }
        return nil
    }
    
    /// Reconciles remote members present in activeRoom against the set of member IDs active on the server.
    /// Remote members missing from the server payload are pruned, while the local player (localMemberId) is protected.
    public func reconcileRemoteMembers(activeServerMemberIds: Set<String>) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.reconcileRemoteMembers(activeServerMemberIds: activeServerMemberIds)
            }
            return
        }
        
        guard var currentRoom = activeRoom else { return }
        var roomChanged = false
        let currentMemberIds = Array(currentRoom.members.keys)
        
        for memberId in currentMemberIds {
            // Protect local player from being pruned
            if let localId = localMemberId, memberId == localId {
                continue
            }
            
            // If a remote member is missing from the server payload, remove them
            if !activeServerMemberIds.contains(memberId) {
                currentRoom.members.removeValue(forKey: memberId)
                memberLatestTimestamps.removeValue(forKey: memberId)
                memberLatestSequences.removeValue(forKey: memberId)
                DeadReckoningEngine.shared.removePlayer(id: memberId)
                roomChanged = true
            }
        }
        
        if roomChanged {
            self.activeRoom = currentRoom
        }
    }
    
    public func fetchRemoteTelemetry(roomId: String) {
        // Change-only check for tactical indicators
        fetchTacticalIndicatorsIfChanged(roomId: roomId)
        
        guard let url = URL(string: "\(databaseURL)/telemetry/\(roomId).json\(authParam())") else { return }
        
        urlSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            
            if let httpRes = response as? HTTPURLResponse, !(200...299).contains(httpRes.statusCode) {
                return
            }
            
            let metadataKeys: Set<String> = ["createdAt", "expireAt", "lastActivityTimestamp", "ttl", "updatedAt"]
            let jsonDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let serverMemberIds: Set<String> = jsonDict != nil
                ? Set(jsonDict!.keys.filter { !$0.starts(with: "_") && !metadataKeys.contains($0) })
                : []
            
            var batchPackets: [TelemetryPacket] = []
            if let dict = jsonDict {
                for (memberId, rawValue) in dict {
                    if memberId.starts(with: "_") || metadataKeys.contains(memberId) {
                        continue
                    }
                    if let localId = self.localMemberId, memberId == localId {
                        continue
                    }
                    if let packet = FirebaseSyncManager.parseTelemetryPacket(memberId: memberId, roomId: roomId, rawValue: rawValue) {
                        batchPackets.append(packet)
                    }
                }
            }
            
            if !batchPackets.isEmpty {
                self.validateAndProcessPackets(batchPackets)
            }
            
            // Reconcile remote members: prune any remote member missing from server response
            self.reconcileRemoteMembers(activeServerMemberIds: serverMemberIds)
        }.resume()
    }
    
    // MARK: - Server-Sent Events (SSE) Streaming & Delta Parsing (Method 2)
    
    public func flushPendingSSETelemetry() {
        let batch = Array(self.ssePendingPackets.values)
        self.ssePendingPackets.removeAll(keepingCapacity: true)
        self.sseFlushPending = false
        if !batch.isEmpty {
            self.validateAndProcessPackets(batch)
        }
    }

    /// Processes a single member's raw telemetry object (compact array or JSON dictionary).
    /// Packets are accumulated into a per-runloop burst buffer and flushed as a single batch
    /// so `activeRoom` is assigned exactly once per SSE event group (not once per member).
    public func processRawMemberTelemetry(memberId: String, roomId: String, rawValue: Any) {
        let metadataKeys: Set<String> = ["createdAt", "expireAt", "lastActivityTimestamp", "ttl", "updatedAt"]
        if memberId.starts(with: "_") || metadataKeys.contains(memberId) {
            return
        }
        if let localId = localMemberId, memberId == localId {
            return
        }
        guard let packet = FirebaseSyncManager.parseTelemetryPacket(memberId: memberId, roomId: roomId, rawValue: rawValue) else { return }
        
        let enqueue = { [weak self] in
            guard let self = self else { return }
            self.ssePendingPackets[memberId] = packet
            
            guard !self.sseFlushPending else { return }
            self.sseFlushPending = true
            
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingSSETelemetry()
            }
        }
        
        if Thread.isMainThread {
            enqueue()
        } else {
            DispatchQueue.main.async(execute: enqueue)
        }
    }
    
    /// Parses Server-Sent Events (SSE) stream frames from Firebase Realtime Database.
    /// Firebase SSE format:
    ///   event: put / patch / keep-alive
    ///   data: {"path": "/", "data": { ... }} OR {"path": "/MEMBER_ID", "data": [ ... ]}
    public func parseSSEEvent(event: String, dataString: String, roomId: String) {
        guard event == "put" || event == "patch" else { return }
        guard let data = dataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        let path = json["path"] as? String ?? "/"
        let payloadData = json["data"]
        
        if path == "/" {
            let metadataKeys: Set<String> = ["createdAt", "expireAt", "lastActivityTimestamp", "ttl", "updatedAt"]
            let membersDict = payloadData as? [String: Any]
            let serverMemberIds: Set<String> = membersDict != nil
                ? Set(membersDict!.keys.filter { !$0.starts(with: "_") && !metadataKeys.contains($0) })
                : []
            var batchPackets: [TelemetryPacket] = []
            if let dict = membersDict {
                for (memberId, rawValue) in dict {
                    if memberId.starts(with: "_") || metadataKeys.contains(memberId) {
                        continue
                    }
                    if let localId = self.localMemberId, memberId == localId {
                        continue
                    }
                    if let packet = FirebaseSyncManager.parseTelemetryPacket(memberId: memberId, roomId: roomId, rawValue: rawValue) {
                        batchPackets.append(packet)
                    }
                }
            }
            if !batchPackets.isEmpty {
                validateAndProcessPackets(batchPackets)
            }
            reconcileRemoteMembers(activeServerMemberIds: serverMemberIds)
        } else {
            let memberId = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !memberId.isEmpty {
                if let rawValue = payloadData, !(rawValue is NSNull) {
                    processRawMemberTelemetry(memberId: memberId, roomId: roomId, rawValue: rawValue)
                    flushPendingSSETelemetry()
                } else if payloadData == nil || payloadData is NSNull {
                    if let localId = localMemberId, memberId != localId {
                        removeMember(id: memberId)
                    }
                }
            }
        }
    }
    
    private func authParam() -> String {
        if let token = authToken, !token.isEmpty {
            return "?auth=\(token)"
        }
        return ""
    }
}
