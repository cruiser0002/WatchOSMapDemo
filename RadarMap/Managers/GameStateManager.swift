import Foundation
import Combine
import CoreLocation
import SwiftUI

public final class GameStateManager: ObservableObject {
    @Published public var myCallsign: String {
        didSet {
            UserDefaults.standard.set(myCallsign, forKey: "user_callsign")
            let oldId = myMemberId
            myMemberId = myCallsign
            updateLocalMember(oldId: oldId)
        }
    }
    @Published public var myMemberId: String
    @Published public var selectedMapStyle: TacticalMapStyle = .radar
    @Published public var radarColorTheme: RadarColorTheme = .green {
        didSet {
            UserDefaults.standard.set(radarColorTheme.rawValue, forKey: "radar_color_theme")
        }
    }
    @Published public var isHosting: Bool = false
    @Published public var isInitiatingHost: Bool = false
    @Published public var isJoining: Bool = false
    @Published public var showPaywallSheet: Bool = false
    @Published public var isDead: Bool = false
    @Published public var errorMessage: String? = nil
    
    public var isCurrentMemberHost: Bool {
        if isHosting { return true }
        guard let room = firebaseManager.activeRoom else { return false }
        return room.hostId == myMemberId || (room.members[myMemberId]?.isHost == true)
    }
    
    // Dependencies
    public let locationHeadingManager = LocationHeadingManager()
    public let healthKitManager = HealthKitManager()
    public let bluetoothManager = BluetoothDiscoveryManager()
    public let firebaseManager = FirebaseSyncManager()
    public let subscriptionManager = SubscriptionManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var localSequenceCounter: Int64 = 0
    private var timer: AnyCancellable?
    
    public init() {
        let savedCallsign = UserDefaults.standard.string(forKey: "user_callsign") ?? "GHOST-1"
        self.myCallsign = savedCallsign
        self.myMemberId = savedCallsign
        
        if let savedTheme = UserDefaults.standard.string(forKey: "radar_color_theme"),
           let theme = RadarColorTheme(rawValue: savedTheme) {
            self.radarColorTheme = theme
        }
        
        bindManagers()
    }
    
    private func bindManagers() {
        // Forward objectWillChange from child managers so SwiftUI views re-render
        firebaseManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        locationHeadingManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        healthKitManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        bluetoothManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        subscriptionManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        firebaseManager.$errorMessage
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)
        // Stream location updates
        locationHeadingManager.$userLocation
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.broadcastLocalTelemetry()
            }
            .store(in: &cancellables)
        
        // Stream heading updates
        locationHeadingManager.$userHeading
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.broadcastLocalTelemetry()
            }
            .store(in: &cancellables)
        
        // Stream heart rate updates
        healthKitManager.$currentHeartRate
            .sink { [weak self] _ in
                self?.broadcastLocalTelemetry()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Game Lifecycle
    
    public func startTacticalSession() {
        locationHeadingManager.requestPermissions()
        locationHeadingManager.startUpdates()
        healthKitManager.requestAuthorization { [weak self] _ in
            self?.healthKitManager.startLiveHeartRateSession()
        }
        
        // Periodic heartbeat broadcast (every 1 second)
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.broadcastLocalTelemetry()
            }
    }
    
    public func stopTacticalSession() {
        locationHeadingManager.stopUpdates()
        healthKitManager.stopLiveHeartRateSession()
        bluetoothManager.stopAdvertising()
        bluetoothManager.stopScanning()
        timer?.cancel()
        timer = nil
        isHosting = false
        isInitiatingHost = false
        isJoining = false
    }
    
    // MARK: - Room Actions
    
    @discardableResult
    public func hostRoom(name: String, pin: String? = nil, completion: ((Bool) -> Void)? = nil) -> Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let squadId = cleanedName.isEmpty ? "SQUAD-\(String(UUID().uuidString.prefix(4)))" : cleanedName
        let hostMember = makeCurrentSquadMember(isHost: true)
        
        let cleanedPin = pin?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPass = (cleanedPin?.isEmpty == false)
        let passHash = hasPass ? FirebaseSyncManager.hashPassword(cleanedPin!, salt: squadId) : nil
        
        // Capacity: 4 (Free) or 999 (Pro)
        let capacity = subscriptionManager.hasUnlimitedSquadUnlock ? 999 : 4
        
        let room = SquadRoom(
            id: squadId,
            hostId: myMemberId,
            maxCapacity: capacity,
            hasPassword: hasPass,
            passwordHash: passHash,
            isBluetoothAdvertising: true,
            members: [myMemberId: hostMember]
        )
        
        isJoining = false
        isInitiatingHost = true
        isHosting = false
        errorMessage = nil
        
        firebaseManager.createRoom(room) { [weak self] result in
            guard let self = self else { return }
            self.isInitiatingHost = false
            switch result {
            case .success(let activeRoom):
                self.isHosting = true
                self.bluetoothManager.startAdvertisingRoom(activeRoom)
                self.startTacticalSession()
                completion?(true)
            case .failure(let error):
                self.isHosting = false
                self.errorMessage = error.localizedDescription
                completion?(false)
            }
        }
        return true
    }
    
    public func joinRoom(id: String, name: String? = nil, pin: String? = nil, completion: ((Bool) -> Void)? = nil) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanId.isEmpty else {
            completion?(false)
            return
        }
        
        isHosting = false
        isInitiatingHost = false
        isJoining = true
        errorMessage = nil
        
        let localMember = makeCurrentSquadMember(isHost: false)
        let cleanedPin = pin?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        firebaseManager.joinRoom(id: cleanId, member: localMember, pin: cleanedPin) { [weak self] result in
            guard let self = self else { return }
            self.isJoining = false
            switch result {
            case .success:
                self.startTacticalSession()
                completion?(true)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                completion?(false)
            }
        }
    }
    
    public func leaveCurrentRoom(completion: ((Bool) -> Void)? = nil) {
        let host = isCurrentMemberHost
        let memberId = myMemberId
        stopTacticalSession()
        if let room = firebaseManager.activeRoom {
            if host {
                firebaseManager.deleteRoom(roomId: room.id, completion: completion)
            } else {
                firebaseManager.removePlayerEntry(roomId: room.id, memberId: memberId, completion: completion)
            }
        } else {
            firebaseManager.leaveRoom(isHost: host, memberId: memberId)
            completion?(true)
        }
    }
    
    public func setDead(_ dead: Bool) {
        isDead = dead
        if var room = firebaseManager.activeRoom, var member = room.members[myMemberId] {
            member.status = dead ? .downed : .active
            member.heartRate = dead ? 0.0 : (healthKitManager.currentHeartRate > 0 ? healthKitManager.currentHeartRate : 75.0)
            room.members[myMemberId] = member
            firebaseManager.updateMember(member)
        }
        broadcastLocalTelemetry()
    }
    
    // MARK: - Telemetry Dispatch
    
    private func makeCurrentSquadMember(isHost: Bool) -> SquadMember {
        let loc = locationHeadingManager.userLocation?.coordinate ?? (firebaseManager.activeRoom?.members[myMemberId]?.coordinate ?? CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417))
        let heading = locationHeadingManager.userHeading?.trueHeading ?? 0.0
        let hr = isDead ? 0.0 : (healthKitManager.currentHeartRate > 0 ? healthKitManager.currentHeartRate : 75.0)
        
        return SquadMember(
            id: myMemberId,
            callsign: myCallsign,
            latitude: loc.latitude,
            longitude: loc.longitude,
            heading: heading,
            heartRate: hr,
            batteryLevel: 0.95,
            lastUpdatedTimestamp: Date().timeIntervalSince1970,
            sequenceNumber: localSequenceCounter,
            status: isDead ? .downed : .active,
            isHost: isHost
        )
    }
    
    private func updateLocalMember(oldId: String? = nil) {
        guard let room = firebaseManager.activeRoom else { return }
        let lookupId = oldId ?? myMemberId
        guard let member = room.members[lookupId] ?? room.members[myMemberId] else { return }
        
        if let oldId = oldId, oldId != myMemberId {
            firebaseManager.removeMember(id: oldId)
        }
        
        let updatedMember = SquadMember(
            id: myMemberId,
            callsign: myCallsign,
            latitude: member.latitude,
            longitude: member.longitude,
            altitude: member.altitude,
            heading: member.heading,
            heartRate: member.heartRate,
            batteryLevel: member.batteryLevel,
            lastUpdatedTimestamp: member.lastUpdatedTimestamp,
            sequenceNumber: member.sequenceNumber,
            status: member.status,
            isHost: member.isHost,
            colorHex: member.colorHex
        )
        firebaseManager.updateMember(updatedMember)
    }
    
    private func broadcastLocalTelemetry() {
        guard let room = firebaseManager.activeRoom else { return }
        localSequenceCounter += 1
        
        let loc = locationHeadingManager.userLocation?.coordinate ?? (firebaseManager.activeRoom?.members[myMemberId]?.coordinate ?? CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417))
        let alt = locationHeadingManager.userLocation?.altitude
        let heading = locationHeadingManager.userHeading?.trueHeading ?? 0.0
        
        // KIA Flatline Rule: 0.0 BPM if KIA/dead, otherwise live HealthKit reading
        let hr: Double = isDead ? 0.0 : (healthKitManager.currentHeartRate > 0 ? healthKitManager.currentHeartRate : 75.0)
        
        let packet = TelemetryPacket(
            memberId: myMemberId,
            roomId: room.id,
            latitude: loc.latitude,
            longitude: loc.longitude,
            altitude: alt,
            heading: heading,
            heartRate: hr,
            timestamp: Date().timeIntervalSince1970,
            sequenceNumber: localSequenceCounter
        )
        
        firebaseManager.sendTelemetryPacket(packet)
    }
}
