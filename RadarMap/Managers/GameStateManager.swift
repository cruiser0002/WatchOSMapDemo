import Foundation
import Combine
import CoreLocation
import SwiftUI

public final class GameStateManager: ObservableObject {
    @Published public var myCallsign: String {
        didSet {
            UserDefaults.standard.set(myCallsign, forKey: AppConstants.Storage.userCallsignKey)
            updateLocalMember()
        }
    }
    @Published public var myMemberId: String {
        didSet {
            firebaseManager.localMemberId = myMemberId
        }
    }
    @Published public var selectedMapStyle: TacticalMapStyle = .radar
    @Published public var radarColorTheme: RadarColorTheme = .green {
        didSet {
            UserDefaults.standard.set(radarColorTheme.rawValue, forKey: AppConstants.Storage.radarColorThemeKey)
        }
    }
    @Published public var savedRoomName: String {
        didSet {
            UserDefaults.standard.set(savedRoomName, forKey: AppConstants.Storage.savedRoomNameKey)
        }
    }
    @Published public var savedPin: String {
        didSet {
            UserDefaults.standard.set(savedPin, forKey: AppConstants.Storage.savedPinKey)
        }
    }
    @Published public var isHosting: Bool = false
    @Published public var isInitiatingHost: Bool = false
    @Published public var isJoining: Bool = false
    @Published public var showPaywallSheet: Bool = false
    @Published public var isDead: Bool = false
    @Published public var errorMessage: String? = nil
    
    // Single Source of Truth for Map State (Scale, Center, Zoom across all Views)
    @Published public var radarScaleMeters: Double = AppConstants.UI.RadarScale.defaultScaleMeters
    @Published public var currentMapCenter: CLLocationCoordinate2D? = nil
    @Published public var radarCenterTrigger: Int = 0
    
    public var currentMapSpanDelta: Double {
        get {
            AppConstants.UI.RadarScale.mapSpanDelta(forRadarScaleMeters: radarScaleMeters)
        }
        set {
            radarScaleMeters = AppConstants.UI.RadarScale.radarScaleMeters(forMapSpanDelta: newValue)
        }
    }
    
    public var currentScaleText: String {
        let screenHeight: Double = AppConstants.UI.ScaleRuler.referenceScreenHeight
        let maxRadius: Double = screenHeight * AppConstants.UI.RadarScale.radarRadiusRatio
        let rulerWidthPoints: Double = AppConstants.UI.ScaleRuler.rulerWidthPoints
        let rulerMeters = rulerWidthPoints * (radarScaleMeters / maxRadius)
        return AppConstants.UI.ScaleRuler.formatRulerDistance(meters: rulerMeters)
    }
    
    public func resetMapToDefaultCenterAndZoom() {
        radarScaleMeters = AppConstants.UI.RadarScale.defaultScaleMeters
        currentMapCenter = nil
        radarCenterTrigger += 1
    }
    
    // Login Field Error States
    @Published public var callsignError: Bool = false
    @Published public var squadNameError: Bool = false
    @Published public var pinError: Bool = false
    
    public func clearFieldErrors() {
        callsignError = false
        squadNameError = false
        pinError = false
    }
    
    // Pro Tier Tactical Indicators
    @Published public var pendingIndicatorPlacementType: TacticalIndicatorType? = nil
    @Published public var showIndicatorMenuSheet: Bool = false
    @Published public var localIndicators: [String: TacticalIndicator] = [:]
    
    public var allTacticalIndicators: [TacticalIndicator] {
        guard let room = firebaseManager.activeRoom else {
            return localIndicators.isEmpty ? [] : Array(localIndicators.values)
        }
        
        guard !room.indicators.isEmpty else { return [] }
        let indicators = Array(room.indicators.values)
        
        let needsResolution = indicators.contains { $0.placedByCallsign == nil || $0.placedByCallsign?.isEmpty == true }
        guard needsResolution else { return indicators }
        
        return indicators.map { ind in
            if (ind.placedByCallsign == nil || ind.placedByCallsign?.isEmpty == true),
               let member = room.members[ind.placedByMemberId] {
                var updated = ind
                updated.placedByCallsign = member.callsign
                return updated
            }
            return ind
        }
    }
    
    public var isProUser: Bool {
        subscriptionManager.hasUnlimitedSquadUnlock
    }
    
    @Published public var adaptiveUploadInterval: TimeInterval = AppConstants.Timing.AdaptiveRate.baselineInterval
    public var lastUploadTimestamp: TimeInterval = 0.0
    
    // Method 1: Dead Reckoning & Telemetry Delta Gating State
    public var lastSentLocation: CLLocation? = nil
    public var lastSentHeading: Double? = nil
    public var lastSentHeartRate: Double? = nil
    public var lastSentIsDead: Bool? = nil
    public var lastSentTimestamp: TimeInterval = 0.0
    public var totalTelemetryUploadsEmitted: Int = 0
    public var totalTelemetryUploadsGated: Int = 0
    
    public var isCurrentMemberHost: Bool {
        if isHosting { return true }
        guard let room = firebaseManager.activeRoom else { return false }
        return room.hostId == myMemberId || (room.members[myMemberId]?.isHost == true)
    }
    
    /// Live local player member with live location, live blended heading (COD + speed weight), and live health stats.
    public var localPlayerMember: SquadMember {
        let loc = locationHeadingManager.userLocation?.coordinate ?? AppConstants.Location.fallbackCoordinate
        let heading = locationHeadingManager.blendedHeading
        let hr = isDead ? AppConstants.Health.flatlineHeartRate : (healthKitManager.currentHeartRate > 0 ? healthKitManager.currentHeartRate : AppConstants.Health.defaultRestingHeartRate)
        
        return SquadMember(
            id: myMemberId,
            callsign: myCallsign.isEmpty ? "OPERATOR" : myCallsign,
            latitude: loc.latitude,
            longitude: loc.longitude,
            heading: heading,
            heartRate: hr,
            batteryLevel: AppConstants.UI.defaultBatteryLevel,
            lastUpdatedTimestamp: Date().timeIntervalSince1970,
            sequenceNumber: localSequenceCounter,
            status: isDead ? .downed : .active,
            isHost: isCurrentMemberHost
        )
    }
    
    // Dependencies
    public let locationHeadingManager = LocationHeadingManager()
    public let healthKitManager = HealthKitManager()
    public let bluetoothManager = BluetoothDiscoveryManager()
    public let firebaseManager = FirebaseSyncManager()
    public let subscriptionManager = SubscriptionManager()
    public let deadReckoningEngine = DeadReckoningEngine.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var localSequenceCounter: Int64 = 0
    private var timer: AnyCancellable?
    
    public init() {
        let savedCallsign = UserDefaults.standard.string(forKey: AppConstants.Storage.userCallsignKey) ?? ""
        self.myCallsign = savedCallsign
        
        let savedMemberId = UserDefaults.standard.string(forKey: AppConstants.Storage.userMemberIdKey) ?? UUID().uuidString
        UserDefaults.standard.set(savedMemberId, forKey: AppConstants.Storage.userMemberIdKey)
        self.myMemberId = savedMemberId
        self.savedRoomName = UserDefaults.standard.string(forKey: AppConstants.Storage.savedRoomNameKey) ?? ""
        self.savedPin = UserDefaults.standard.string(forKey: AppConstants.Storage.savedPinKey) ?? ""
        
        firebaseManager.localMemberId = savedMemberId
        
        if let savedTheme = UserDefaults.standard.string(forKey: AppConstants.Storage.radarColorThemeKey),
           let theme = RadarColorTheme(rawValue: savedTheme) {
            self.radarColorTheme = theme
        }
        
        bindManagers()
        locationHeadingManager.requestPermissions()
        locationHeadingManager.startUpdates()
    }
    
    private func bindManagers() {
        firebaseManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)
            
        Publishers.CombineLatest(firebaseManager.$activeRoom, firebaseManager.networkQualityMonitor.$connectionGrade)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateAdaptiveUploadInterval()
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
            
        deadReckoningEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        // Stream location updates
        locationHeadingManager.$userLocation
            .compactMap { $0 }
            .sink { [weak self] loc in
                self?.broadcastLocalTelemetry(location: loc, force: false)
            }
            .store(in: &cancellables)
        
        // Stream heart rate updates
        healthKitManager.$currentHeartRate
            .sink { [weak self] hr in
                self?.broadcastLocalTelemetry(heartRate: hr, force: false)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Adaptive Rate Control
    
    /// Stationary upload heartbeat fallback interval (10.0s constant).
    public func currentHeartbeatFallbackInterval() -> TimeInterval {
        return AppConstants.Timing.DeltaGating.heartbeatFallbackIntervalSeconds
    }
    
    public func recalculateAdaptiveUploadInterval() {
        let memberCount = firebaseManager.activeRoom?.members.count ?? 0
        let grade = firebaseManager.networkQualityMonitor.connectionGrade
        
        let calculatedInterval = FirebaseSyncManager.solveUpdateInterval(playerCount: memberCount)
        
        let newInterval: TimeInterval
        if grade == .critical || grade == .offline {
            newInterval = max(AppConstants.Timing.AdaptiveRate.criticalInterval, calculatedInterval)
        } else if grade == .poor {
            newInterval = max(AppConstants.Timing.AdaptiveRate.poorInterval, calculatedInterval)
        } else {
            newInterval = calculatedInterval
        }
        
        if abs(self.adaptiveUploadInterval - newInterval) > AppConstants.Timing.AdaptiveRate.intervalChangeEpsilon {
            self.adaptiveUploadInterval = newInterval
            if timer != nil {
                restartHeartbeatTimer()
            }
        }
    }
    
    private func restartHeartbeatTimer() {
        timer?.cancel()
        let interval = currentHeartbeatFallbackInterval()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.broadcastLocalTelemetry(force: true)
            }
    }
    
    // MARK: - Game Lifecycle
    
    public func startTacticalSession() {
        locationHeadingManager.requestPermissions()
        locationHeadingManager.startUpdates()
        healthKitManager.requestAuthorization { [weak self] _ in
            self?.healthKitManager.startLiveHeartRateSession()
        }
        
        restartHeartbeatTimer()
    }
    
    public func stopTacticalSession() {
        locationHeadingManager.stopUpdates()
        healthKitManager.stopLiveHeartRateSession()
        bluetoothManager.stopAdvertising()
        bluetoothManager.stopScanning()
        timer?.cancel()
        timer = nil
        lastSentLocation = nil
        lastSentHeading = nil
        lastSentHeartRate = nil
        lastSentIsDead = nil
        lastSentTimestamp = 0.0
        isHosting = false
        isInitiatingHost = false
        isJoining = false
    }
    
    public func setWristActive(_ active: Bool) {
        firebaseManager.setWristActive(active)
    }
    
    /// Called when scenePhase becomes active or wrist wakes to trigger instant telemetry refresh
    public func handleAppResume() {
        locationHeadingManager.startUpdates()
        deadReckoningEngine.startInterpolationLoop()
        firebaseManager.setWristActive(true)
    }
    
    /// Called when app goes into background
    public func handleAppSuspend() {
        firebaseManager.setWristActive(false)
    }
    
    /// Triggers an immediate wake burst on interaction/gesture (e.g. double tap, screen tap, digital crown rotation)
    public func triggerWakeBurst() {
        firebaseManager.triggerWakeBurst()
    }
    
    // MARK: - Room Actions
    
    /// Sanitizes PIN input from numerical keyboard or voice dictation,
    /// converting spoken number words to digits, stripping all non-digits,
    /// and clamping length to max 4 digits.
    public static func sanitizePinInput(_ input: String) -> String {
        let wordMapping = AppConstants.UI.pinWordMapping
        
        let lowercased = input.lowercased()
        let tokens = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        var result = ""
        for token in tokens {
            if let digit = wordMapping[token] {
                result.append(digit)
            } else {
                result.append(token.filter { $0.isNumber })
            }
        }
        
        return String(result.prefix(AppConstants.UI.maxPinLength))
    }
    
    @discardableResult
    public func hostRoom(name: String, pin: String? = nil, completion: ((Bool) -> Void)? = nil) -> Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanedCallsign = myCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        
        clearFieldErrors()
        
        if cleanedName.isEmpty {
            squadNameError = true
            let err = FirebaseSyncError.emptyRoomName
            errorMessage = err.localizedDescription
            completion?(false)
            return false
        }
        
        if cleanedCallsign.isEmpty {
            callsignError = true
            let err = FirebaseSyncError.emptyCallsign
            errorMessage = err.localizedDescription
            completion?(false)
            return false
        }
        
        self.savedRoomName = cleanedName
        let squadId = cleanedName
        let hostMember = makeCurrentSquadMember(isHost: true)
        
        let cleanedPin = pin.map { GameStateManager.sanitizePinInput($0) }
        if let cp = cleanedPin, !cp.isEmpty {
            self.savedPin = cp
        }
        let hasPass = (cleanedPin?.isEmpty == false)
        let passHash = hasPass ? FirebaseSyncManager.hashPin(cleanedPin!, salt: squadId) : nil
        
        // Capacity: 4 (Free) or 999 (Pro)
        let capacity = subscriptionManager.hasUnlimitedSquadUnlock ? AppConstants.Subscription.proTierMaxCapacity : AppConstants.Subscription.freeTierMaxCapacity
        
        let room = SquadRoom(
            id: squadId,
            hostId: myMemberId,
            maxCapacity: capacity,
            hasPin: hasPass,
            pinHash: passHash,
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
                self.clearFieldErrors()
                self.bluetoothManager.startAdvertisingRoom(activeRoom)
                self.startTacticalSession()
                completion?(true)
            case .failure(let error):
                self.isHosting = false
                self.errorMessage = error.localizedDescription
                switch error {
                case .roomAlreadyExists, .emptyRoomName:
                    self.squadNameError = true
                case .emptyCallsign, .duplicateCallsign:
                    self.callsignError = true
                default:
                    break
                }
                completion?(false)
            }
        }
        return true
    }
    
    public func joinRoom(id: String, name: String? = nil, pin: String? = nil, onResult: ((Result<SquadRoom, FirebaseSyncError>) -> Void)?) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanCallsign = myCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        
        clearFieldErrors()
        
        if cleanId.isEmpty {
            self.squadNameError = true
            let err = FirebaseSyncError.emptyRoomName
            self.errorMessage = err.localizedDescription
            onResult?(.failure(err))
            return
        }
        
        if cleanCallsign.isEmpty {
            self.callsignError = true
            let err = FirebaseSyncError.emptyCallsign
            self.errorMessage = err.localizedDescription
            onResult?(.failure(err))
            return
        }
        
        self.savedRoomName = cleanId
        
        isHosting = false
        isInitiatingHost = false
        isJoining = true
        errorMessage = nil
        
        let localMember = makeCurrentSquadMember(isHost: false)
        let cleanedPin = pin.map { GameStateManager.sanitizePinInput($0) }
        if let cp = cleanedPin, !cp.isEmpty {
            self.savedPin = cp
        }
        
        firebaseManager.joinRoom(id: cleanId, member: localMember, pin: cleanedPin) { [weak self] result in
            guard let self = self else { return }
            self.isJoining = false
            switch result {
            case .success(let room):
                self.clearFieldErrors()
                self.startTacticalSession()
                onResult?(.success(room))
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                switch error {
                case .duplicateCallsign, .emptyCallsign:
                    self.callsignError = true
                case .roomNotFound, .roomAlreadyExists, .emptyRoomName:
                    self.squadNameError = true
                case .incorrectPin, .incorrectPassword:
                    self.pinError = true
                default:
                    break
                }
                onResult?(.failure(error))
            }
        }
    }
    
    public func joinRoom(id: String, name: String? = nil, pin: String? = nil, completion: ((Bool) -> Void)? = nil) {
        joinRoom(id: id, name: name, pin: pin) { (result: Result<SquadRoom, FirebaseSyncError>) in
            switch result {
            case .success:
                completion?(true)
            case .failure:
                completion?(false)
            }
        }
    }
    
    public func disbandRoom(completion: ((Bool) -> Void)? = nil) {
        stopTacticalSession()
        guard let room = firebaseManager.activeRoom else {
            firebaseManager.leaveRoom(isHost: true, memberId: myMemberId)
            completion?(true)
            return
        }
        firebaseManager.disbandRoom(roomId: room.id, completion: completion)
    }
    
    public func logoutPlayer(completion: ((Bool) -> Void)? = nil) {
        stopTacticalSession()
        guard let room = firebaseManager.activeRoom else {
            firebaseManager.leaveRoom(isHost: false, memberId: myMemberId)
            completion?(true)
            return
        }
        firebaseManager.logoutPlayer(roomId: room.id, memberId: myMemberId, completion: completion)
    }
    
    public func leaveCurrentRoom(completion: ((Bool) -> Void)? = nil) {
        if isCurrentMemberHost {
            disbandRoom(completion: completion)
        } else {
            logoutPlayer(completion: completion)
        }
    }
    
    public func setDead(_ dead: Bool) {
        isDead = dead
        let now = Date().timeIntervalSince1970
        if var room = firebaseManager.activeRoom, var member = room.members[myMemberId] {
            member.status = dead ? .downed : .active
            member.heartRate = dead ? AppConstants.Health.flatlineHeartRate : (healthKitManager.currentHeartRate > 0 ? healthKitManager.currentHeartRate : AppConstants.Health.defaultRestingHeartRate)
            member.lastUpdatedTimestamp = now
            room.members[myMemberId] = member
            firebaseManager.updateMember(member)
        }
        broadcastLocalTelemetry(force: true)
    }
    
    // MARK: - Telemetry Dispatch
    
    private func makeCurrentSquadMember(isHost: Bool) -> SquadMember {
        let loc = locationHeadingManager.userLocation?.coordinate ?? (firebaseManager.activeRoom?.members[myMemberId]?.coordinate ?? AppConstants.Location.fallbackCoordinate)
        let heading = locationHeadingManager.blendedHeading
        let hr = isDead ? AppConstants.Health.flatlineHeartRate : (healthKitManager.currentHeartRate > 0 ? healthKitManager.currentHeartRate : AppConstants.Health.defaultRestingHeartRate)
        
        return SquadMember(
            id: myMemberId,
            callsign: myCallsign,
            latitude: loc.latitude,
            longitude: loc.longitude,
            heading: heading,
            heartRate: hr,
            batteryLevel: AppConstants.UI.defaultBatteryLevel,
            lastUpdatedTimestamp: Date().timeIntervalSince1970,
            sequenceNumber: localSequenceCounter,
            status: isDead ? .downed : .active,
            isHost: isHost
        )
    }
    
    private func updateLocalMember(oldId: String? = nil) {
        guard let room = firebaseManager.activeRoom else { return }
        let lookupId = oldId ?? myMemberId
        guard var member = room.members[lookupId] ?? room.members[myMemberId] else { return }
        
        if let oldId = oldId, oldId != myMemberId {
            firebaseManager.removeMember(id: oldId)
        }
        
        member.callsign = myCallsign
        member.heading = locationHeadingManager.blendedHeading
        member.lastUpdatedTimestamp = Date().timeIntervalSince1970
        firebaseManager.updateMember(member)
    }
    
    /// Evaluates whether a new telemetry state satisfies delta thresholds or heartbeat fallback to trigger an upload.
    public func shouldEmitTelemetry(
        currentLocation: CLLocation,
        currentHeading: Double,
        currentHeartRate: Double,
        currentIsDead: Bool,
        currentTime: TimeInterval,
        force: Bool = false
    ) -> Bool {
        if force { return true }
        
        // Always emit the initial packet
        guard let prevLocation = lastSentLocation,
              let prevHeartRate = lastSentHeartRate,
              let prevIsDead = lastSentIsDead else {
            return true
        }
        
        // 1. Status transition (Alive <-> Downed/KIA) must immediately emit
        if prevIsDead != currentIsDead {
            return true
        }
        
        // 2. Heartbeat fallback: If stationary for >= currentHeartbeatFallbackInterval (staleTimeout / 2.0), emit to prove liveness
        let heartbeatFallback = currentHeartbeatFallbackInterval()
        if (currentTime - lastSentTimestamp) >= heartbeatFallback {
            return true
        }
        
        // 3. Movement threshold: distance moved >= minMovementDeltaMeters (1.5m)
        let distanceMoved = currentLocation.distance(from: prevLocation)
        if distanceMoved >= AppConstants.Timing.DeltaGating.minMovementDeltaMeters {
            return true
        }
        
        // 4. Heart rate threshold: change >= minHeartRateDeltaBpm (5.0 BPM)
        if abs(currentHeartRate - prevHeartRate) >= AppConstants.Timing.DeltaGating.minHeartRateDeltaBpm {
            return true
        }
        
        // All criteria below threshold -> Gate / Suppress upload to conserve bandwidth
        return false
    }
    
    public func broadcastLocalTelemetry(
        location: CLLocation? = nil,
        heading: Double? = nil,
        heartRate: Double? = nil,
        force: Bool = false
    ) {
        guard let room = firebaseManager.activeRoom else { return }
        
        let now = Date().timeIntervalSince1970
        if !force && (now - lastUploadTimestamp) < adaptiveUploadInterval {
            return
        }
        
        let currentLoc = location ?? locationHeadingManager.userLocation ?? CLLocation(latitude: AppConstants.Location.fallbackLatitude, longitude: AppConstants.Location.fallbackLongitude)
        let loc = currentLoc.coordinate
        let alt = currentLoc.altitude
        let currentHeading = heading ?? locationHeadingManager.blendedHeading
        
        // KIA Flatline Rule: 0.0 BPM if KIA/dead, otherwise live HealthKit reading
        let rawHr = heartRate ?? healthKitManager.currentHeartRate
        let currentHr: Double = isDead ? AppConstants.Health.flatlineHeartRate : (rawHr > 0 ? rawHr : AppConstants.Health.defaultRestingHeartRate)
        
        let shouldEmit = shouldEmitTelemetry(
            currentLocation: currentLoc,
            currentHeading: currentHeading,
            currentHeartRate: currentHr,
            currentIsDead: isDead,
            currentTime: now,
            force: force
        )
        
        guard shouldEmit else {
            totalTelemetryUploadsGated += 1
            return
        }
        
        lastUploadTimestamp = now
        totalTelemetryUploadsEmitted += 1
        lastSentLocation = currentLoc
        lastSentHeading = currentHeading
        lastSentHeartRate = currentHr
        lastSentIsDead = isDead
        lastSentTimestamp = now
        
        localSequenceCounter += 1
        
        let packet = TelemetryPacket(
            memberId: myMemberId,
            roomId: room.id,
            latitude: loc.latitude,
            longitude: loc.longitude,
            altitude: alt,
            heading: currentHeading,
            heartRate: currentHr,
            timestamp: now,
            sequenceNumber: localSequenceCounter
        )
        
        firebaseManager.sendTelemetryPacket(packet)
    }
    
    // MARK: - Pro Tier Tactical Indicators Management
    
    public func openIndicatorMenu() {
        guard subscriptionManager.hasUnlimitedSquadUnlock else {
            showPaywallSheet = true
            return
        }
        showIndicatorMenuSheet = true
    }
    
    public func selectIndicatorForPlacement(_ type: TacticalIndicatorType) {
        guard subscriptionManager.hasUnlimitedSquadUnlock else {
            showIndicatorMenuSheet = false
            showPaywallSheet = true
            return
        }
        pendingIndicatorPlacementType = type
        showIndicatorMenuSheet = false
    }
    
    public func cancelIndicatorPlacement() {
        pendingIndicatorPlacementType = nil
    }
    
    public func placeTacticalIndicator(at coordinate: CLLocationCoordinate2D) {
        guard let type = pendingIndicatorPlacementType else { return }
        guard subscriptionManager.hasUnlimitedSquadUnlock else {
            showPaywallSheet = true
            pendingIndicatorPlacementType = nil
            return
        }
        
        let roomId = firebaseManager.activeRoom?.id
        let currentIndicators = allTacticalIndicators
        
        // Rule 1: Squad orders: Only 1 icon of each per player (allowing multiple pro players to distinguish commands)
        if type.category == .squadOrder {
            let existingSameType = currentIndicators.filter { $0.type == type && $0.placedByMemberId == myMemberId }
            for ind in existingSameType {
                removeTacticalIndicator(id: ind.id)
            }
        }
        
        // Rule 2: Enemy indicators: 20 total enemy indicators, oldest gets replaced if we run out
        if type.category == .enemyIndicator {
            let enemyIndicators = allTacticalIndicators.filter { $0.category == .enemyIndicator }
            if enemyIndicators.count >= AppConstants.Subscription.maxEnemyIndicatorsCount {
                // Find the oldest indicator by timestamp
                if let oldest = enemyIndicators.min(by: { $0.timestamp < $1.timestamp }) {
                    removeTacticalIndicator(id: oldest.id)
                }
            }
        }
        
        let newIndicator = TacticalIndicator(
            type: type,
            coordinate: coordinate,
            placedByMemberId: myMemberId,
            placedByCallsign: myCallsign
        )
        
        if let roomId = roomId {
            firebaseManager.addOrUpdateIndicator(roomId: roomId, indicator: newIndicator)
        } else {
            localIndicators[newIndicator.id] = newIndicator
        }
        
        pendingIndicatorPlacementType = nil
    }
    
    public func removeTacticalIndicator(id: String) {
        if let roomId = firebaseManager.activeRoom?.id {
            firebaseManager.removeIndicator(roomId: roomId, indicatorId: id)
        }
        localIndicators.removeValue(forKey: id)
    }
}
