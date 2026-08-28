import Foundation
import Combine
import CoreLocation
import SwiftUI

public final class GameStateManager: ObservableObject {
    @Published public var myCallsign: String {
        didSet {
            UserDefaults.standard.set(myCallsign, forKey: AppConstants.Storage.userCallsignKey)
            updateLocalMember()
            updateLocalPlayerMember()
            updateAllTacticalIndicators()
        }
    }
    @Published public var myMemberId: String {
        didSet {
            firebaseManager.localMemberId = myMemberId
            updateLocalPlayerMember()
            updateOtherSquadMembers()
            updateAllTacticalIndicators()
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
    @Published public var isHosting: Bool = false {
        didSet {
            updateLocalPlayerMember()
        }
    }
    @Published public var isInitiatingHost: Bool = false
    @Published public var isJoining: Bool = false
    @Published public var showPaywallSheet: Bool = false
    @Published public var isDead: Bool = false {
        didSet {
            updateLocalPlayerMember()
        }
    }
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
    @Published public var localIndicators: [String: TacticalIndicator] = [:] {
        didSet {
            updateAllTacticalIndicators()
        }
    }
    
    @Published public private(set) var allTacticalIndicators: [TacticalIndicator] = []
    
    public func updateAllTacticalIndicators(room: SquadRoom? = nil) {
        let currentRoom = room ?? firebaseManager.activeRoom
        let rawIndicators: [TacticalIndicator]
        if let currentRoom = currentRoom {
            guard !currentRoom.indicators.isEmpty else {
                if !allTacticalIndicators.isEmpty { allTacticalIndicators = [] }
                return
            }
            rawIndicators = Array(currentRoom.indicators.values)
        } else {
            guard !localIndicators.isEmpty else {
                if !allTacticalIndicators.isEmpty { allTacticalIndicators = [] }
                return
            }
            rawIndicators = Array(localIndicators.values)
        }
        
        // Fast path: if the indicator IDs and count are unchanged (the common case when only
        // member coordinates are being updated), skip the string-trim map entirely.
        // Callsigns are static after placement so there's nothing to re-resolve.
        let rawIds = rawIndicators.map(\.id).sorted()
        let existingIds = allTacticalIndicators.map(\.id).sorted()
        if rawIds == existingIds && !rawIndicators.isEmpty {
            return
        }
        
        let mapped = rawIndicators.map { ind -> TacticalIndicator in
            var updated = ind
            let trimmed = updated.placedByCallsign?.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == nil || trimmed?.isEmpty == true {
                if let member = currentRoom?.members[ind.placedByMemberId], !member.callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updated.placedByCallsign = member.callsign
                } else if ind.placedByMemberId == myMemberId {
                    let clean = myCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.placedByCallsign = clean.isEmpty ? "OPERATOR" : clean
                } else {
                    updated.placedByCallsign = "OPERATOR"
                }
            }
            return updated
        }
        if allTacticalIndicators != mapped {
            allTacticalIndicators = mapped
            enforceHostTacticalIndicatorMaintenance()
        }
    }
    
    private var isEnforcingMaintenance = false
    
    public func enforceHostTacticalIndicatorMaintenance() {
        guard !isEnforcingMaintenance else { return }
        let isHost = isCurrentMemberHost || (firebaseManager.activeRoom == nil)
        guard isHost else { return }
        
        isEnforcingMaintenance = true
        defer { isEnforcingMaintenance = false }
        
        let currentRoom = firebaseManager.activeRoom
        let currentIndicators: [TacticalIndicator] = currentRoom != nil ? Array(currentRoom!.indicators.values) : Array(localIndicators.values)
        
        let enemyIndicators = currentIndicators.filter { $0.category == .enemyIndicator }
        let now = Date()
        
        // 1. Evict indicators exceeding max capacity (keep 20 newest)
        if enemyIndicators.count > AppConstants.Subscription.maxEnemyIndicatorsCount {
            let sortedByTimestamp = enemyIndicators.sorted(by: { $0.timestamp < $1.timestamp })
            let overflowCount = enemyIndicators.count - AppConstants.Subscription.maxEnemyIndicatorsCount
            let toEvict = sortedByTimestamp.prefix(overflowCount)
            for indicator in toEvict {
                removeTacticalIndicator(id: indicator.id)
            }
        }
        
        // 2. Evict expired indicators (fully faded > 5 mins)
        let expired = currentIndicators.filter { $0.category == .enemyIndicator && $0.isFullyFaded(referenceDate: now) }
        for indicator in expired {
            removeTacticalIndicator(id: indicator.id)
        }
    }
    
    @Published public private(set) var otherSquadMembers: [SquadMember] = []
    
    public func updateOtherSquadMembers(room: SquadRoom? = nil) {
        let currentRoom = room ?? firebaseManager.activeRoom
        guard let currentRoom = currentRoom else {
            if !otherSquadMembers.isEmpty { otherSquadMembers = [] }
            return
        }
        let filtered = currentRoom.members.values.filter { $0.id != myMemberId }
        otherSquadMembers = Array(filtered)
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
    
    /// Cached host status — updated via Combine only when isHosting, activeRoom, or myMemberId
    /// changes, rather than re-evaluating a dictionary lookup on every sensor tick.
    @Published public private(set) var isCurrentMemberHost: Bool = false
    
    /// Live local player member with live smoothed location, live blended heading (COD + speed weight), and live health stats.
    @Published public private(set) var localPlayerMember: SquadMember = SquadMember(
        id: "",
        callsign: "OPERATOR",
        latitude: AppConstants.Location.fallbackLatitude,
        longitude: AppConstants.Location.fallbackLongitude,
        heading: 0,
        heartRate: AppConstants.Health.defaultRestingHeartRate,
        batteryLevel: AppConstants.UI.defaultBatteryLevel,
        lastUpdatedTimestamp: 0,
        sequenceNumber: 0,
        status: .active,
        isHost: false
    )
    
    public func updateLocalPlayerMember() {
        let rawLoc = locationHeadingManager.userLocation?.coordinate ?? AppConstants.Location.fallbackCoordinate
        let rawHeading = locationHeadingManager.blendedHeading
        let coord = deadReckoningEngine.smoothedLocalCoordinate(fallback: rawLoc)
        let heading = deadReckoningEngine.smoothedLocalHeading(fallback: rawHeading)
        let hr = isDead ? AppConstants.Health.flatlineHeartRate : (healthKitManager.currentHeartRate > 0 ? healthKitManager.currentHeartRate : AppConstants.Health.defaultRestingHeartRate)
        
        localPlayerMember = SquadMember(
            id: myMemberId,
            callsign: myCallsign.isEmpty ? "OPERATOR" : myCallsign,
            latitude: coord.latitude,
            longitude: coord.longitude,
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
    public let firebaseManager = FirebaseSyncManager()
    public let subscriptionManager = SubscriptionManager()
    public let deadReckoningEngine = DeadReckoningEngine.shared
    public let watchConnectivityManager = WatchConnectivityManager.shared
    
    private var isApplyingRemoteSync: Bool = false
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
        
        updateLocalPlayerMember()
        updateOtherSquadMembers()
        updateAllTacticalIndicators()
        
        setupWatchConnectivity()
        bindManagers()
        locationHeadingManager.requestPermissions()
        locationHeadingManager.startUpdates()
        
        #if os(iOS)
        watchConnectivityManager.sendIdentityHandshake(memberId: savedMemberId)
        #endif
    }
    
    private func setupWatchConnectivity() {
        watchConnectivityManager.onConfigReceived = { [weak self] payload in
            guard let self = self else { return }
            self.isApplyingRemoteSync = true
            if let cs = payload.callsign, self.myCallsign != cs {
                self.myCallsign = cs
            }
            if let rn = payload.roomName, self.savedRoomName != rn {
                self.savedRoomName = rn
            }
            if let pin = payload.pin, self.savedPin != pin {
                self.savedPin = pin
            }
            if let themeStr = payload.theme, let theme = RadarColorTheme(rawValue: themeStr), self.radarColorTheme != theme {
                self.radarColorTheme = theme
            }
            self.isApplyingRemoteSync = false
        }
        
        watchConnectivityManager.onRoomActionReceived = { [weak self] action in
            guard let self = self else { return }
            self.isApplyingRemoteSync = true
            switch action.actionType {
            case AppConstants.WatchConnectivity.ActionType.host:
                if self.firebaseManager.activeRoom?.id != action.roomName {
                    self.hostRoom(name: action.roomName, pin: action.pin)
                }
            case AppConstants.WatchConnectivity.ActionType.join:
                if self.firebaseManager.activeRoom?.id != action.roomName {
                    self.joinRoom(id: action.roomName, name: "Squad \(action.roomName)", pin: action.pin)
                }
            case AppConstants.WatchConnectivity.ActionType.leave:
                self.logoutPlayer()
            case AppConstants.WatchConnectivity.ActionType.disband:
                self.disbandRoom()
            default:
                break
            }
            self.isApplyingRemoteSync = false
        }
        
        watchConnectivityManager.onIdentityReceived = { [weak self] remoteMemberId in
            guard let self = self else { return }
            #if os(watchOS)
            if self.myMemberId != remoteMemberId && !remoteMemberId.isEmpty {
                self.myMemberId = remoteMemberId
                UserDefaults.standard.set(remoteMemberId, forKey: AppConstants.Storage.userMemberIdKey)
            }
            #endif
        }
    }
    
    private func bindManagers() {
        firebaseManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)
        
        // Update cached isCurrentMemberHost whenever its inputs change.
        // This replaces the per-tick dictionary lookup that was inside updateLocalPlayerMember().
        Publishers.CombineLatest3(
            $isHosting,
            firebaseManager.$activeRoom,
            $myMemberId
        )
        .map { isHosting, room, memberId -> Bool in
            if isHosting { return true }
            guard let room = room else { return false }
            return room.hostId == memberId || (room.members[memberId]?.isHost == true)
        }
        .assign(to: &$isCurrentMemberHost)
            
        firebaseManager.$activeRoom
            .sink { [weak self] newRoom in
                if Thread.isMainThread {
                    self?.updateOtherSquadMembers(room: newRoom)
                    self?.updateAllTacticalIndicators(room: newRoom)
                    self?.updateLocalPlayerMember()
                } else {
                    DispatchQueue.main.async {
                        self?.updateOtherSquadMembers(room: newRoom)
                        self?.updateAllTacticalIndicators(room: newRoom)
                        self?.updateLocalPlayerMember()
                    }
                }
            }
            .store(in: &cancellables)
            
        Publishers.CombineLatest(firebaseManager.$activeRoom, firebaseManager.networkQualityMonitor.$connectionGrade)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateAdaptiveUploadInterval()
            }
            .store(in: &cancellables)
            
        Publishers.CombineLatest4($myCallsign, $savedRoomName, $savedPin, $radarColorTheme)
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] callsign, roomName, pin, theme in
                guard let self = self, !self.isApplyingRemoteSync else { return }
                self.watchConnectivityManager.sendConfigUpdate(
                    callsign: callsign,
                    roomName: roomName,
                    pin: pin,
                    theme: theme.rawValue
                )
            }
            .store(in: &cancellables)
            
        // Stream location updates to local dead-reckoning engine and network telemetry.
        // This pipeline is kept separate because it also drives broadcastLocalTelemetry.
        locationHeadingManager.$userLocation
            .compactMap { $0 }
            .sink { [weak self] loc in
                guard let self = self else { return }
                self.deadReckoningEngine.updateLocalPlayer(
                    coordinate: loc.coordinate,
                    heading: self.locationHeadingManager.blendedHeading
                )
                self.broadcastLocalTelemetry(location: loc, force: false)
            }
            .store(in: &cancellables)
            
        // Stream blended heading updates to dead-reckoning engine for smooth compass rotation.
        locationHeadingManager.$blendedHeading
            .sink { [weak self] heading in
                self?.deadReckoningEngine.updateLocalPlayerHeading(heading)
            }
            .store(in: &cancellables)
        
        // Stream heart rate updates for network broadcast.
        healthKitManager.$currentHeartRate
            .sink { [weak self] hr in
                self?.broadcastLocalTelemetry(heartRate: hr, force: false)
            }
            .store(in: &cancellables)
        
        // Coalesced local-member refresh: merges all sensor change signals and debounces to a
        // single updateLocalPlayerMember() call per runloop turn, preventing 3–5 redundant
        // rebuilds of `localPlayerMember` when dead-reckoning, location, and heading all fire
        // within the same tick.
        Publishers.MergeMany(
            locationHeadingManager.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            healthKitManager.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            deadReckoningEngine.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            locationHeadingManager.$userLocation.map { _ in () }.eraseToAnyPublisher(),
            locationHeadingManager.$blendedHeading.map { _ in () }.eraseToAnyPublisher(),
            healthKitManager.$currentHeartRate.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .seconds(0), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.updateLocalPlayerMember()
            self?.objectWillChange.send()
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
        purgeLocalSessionAndIcons()
    }
    
    /// Unified purging function applied across all 4 network actions: Join, Host, Disband, and Leave.
    /// Resets all local team member lists, tactical indicators, remote dead-reckoning states, and sync manager sessions.
    public func purgeLocalSessionAndIcons() {
        localIndicators.removeAll()
        allTacticalIndicators.removeAll()
        pendingIndicatorPlacementType = nil
        otherSquadMembers.removeAll()
        deadReckoningEngine.clearRemoteMembers()
        firebaseManager.resetLocalSessionAndIcons()
        updateLocalPlayerMember()
    }
    
    /// Alias for backward compatibility
    public func purgeIconsOnLogout() {
        purgeLocalSessionAndIcons()
    }
    
    public func setWristActive(_ active: Bool) {
        firebaseManager.setWristActive(active)
        if active {
            locationHeadingManager.exitLowPowerMode()
            deadReckoningEngine.startInterpolationLoop()
        } else {
            locationHeadingManager.enterLowPowerMode()
            deadReckoningEngine.stopInterpolationLoop()
        }
    }
    
    /// Called when scenePhase becomes active or wrist wakes to trigger instant telemetry refresh
    public func handleAppResume() {
        locationHeadingManager.exitLowPowerMode()
        locationHeadingManager.startUpdates()
        deadReckoningEngine.startInterpolationLoop()
        healthKitManager.startLiveHeartRateSession()
        firebaseManager.setWristActive(true)
    }
    
    /// Called when app goes into background or is suspended
    public func handleAppSuspend() {
        locationHeadingManager.enterLowPowerMode()
        deadReckoningEngine.stopInterpolationLoop()
        healthKitManager.stopLiveHeartRateSession()
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
        purgeLocalSessionAndIcons()
        
        if !isApplyingRemoteSync {
            watchConnectivityManager.sendRoomAction(
                actionType: AppConstants.WatchConnectivity.ActionType.host,
                roomName: cleanedName,
                pin: cleanedPin,
                isHosting: true
            )
        }
        
        firebaseManager.createRoom(room) { [weak self] result in
            guard let self = self else { return }
            self.isInitiatingHost = false
            switch result {
            case .success:
                self.isHosting = true
                self.clearFieldErrors()
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
        purgeLocalSessionAndIcons()
        
        let cleanedPin = pin.map { GameStateManager.sanitizePinInput($0) }
        if let cp = cleanedPin, !cp.isEmpty {
            self.savedPin = cp
        }
        
        if !isApplyingRemoteSync {
            watchConnectivityManager.sendRoomAction(
                actionType: AppConstants.WatchConnectivity.ActionType.join,
                roomName: cleanId,
                pin: cleanedPin,
                isHosting: false
            )
        }
        
        let localMember = makeCurrentSquadMember(isHost: false)
        
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
        let roomId = firebaseManager.activeRoom?.id
        if !isApplyingRemoteSync {
            watchConnectivityManager.sendRoomAction(
                actionType: AppConstants.WatchConnectivity.ActionType.disband,
                roomName: savedRoomName
            )
        }
        stopTacticalSession()
        purgeLocalSessionAndIcons()
        guard let id = roomId else {
            firebaseManager.leaveRoom(isHost: true, memberId: myMemberId)
            purgeLocalSessionAndIcons()
            completion?(true)
            return
        }
        firebaseManager.disbandRoom(roomId: id) { [weak self] success in
            self?.purgeLocalSessionAndIcons()
            completion?(success)
        }
    }
    
    public func logoutPlayer(completion: ((Bool) -> Void)? = nil) {
        let roomId = firebaseManager.activeRoom?.id
        if !isApplyingRemoteSync {
            watchConnectivityManager.sendRoomAction(
                actionType: AppConstants.WatchConnectivity.ActionType.leave,
                roomName: savedRoomName
            )
        }
        stopTacticalSession()
        purgeLocalSessionAndIcons()
        guard let id = roomId else {
            firebaseManager.leaveRoom(isHost: false, memberId: myMemberId)
            purgeLocalSessionAndIcons()
            completion?(true)
            return
        }
        firebaseManager.logoutPlayer(roomId: id, memberId: myMemberId) { [weak self] success in
            self?.purgeLocalSessionAndIcons()
            completion?(success)
        }
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
        
        let cleanCallsign = myCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCallsign = cleanCallsign.isEmpty ? (firebaseManager.activeRoom?.members[myMemberId]?.callsign ?? "OPERATOR") : cleanCallsign
        
        let newIndicator = TacticalIndicator(
            type: type,
            coordinate: coordinate,
            placedByMemberId: myMemberId,
            placedByCallsign: resolvedCallsign
        )
        
        if let roomId = roomId {
            firebaseManager.addOrUpdateIndicator(roomId: roomId, indicator: newIndicator)
        } else {
            localIndicators[newIndicator.id] = newIndicator
        }
        updateAllTacticalIndicators()
        enforceHostTacticalIndicatorMaintenance()
        
        pendingIndicatorPlacementType = nil
    }
    
    public func removeTacticalIndicator(id: String) {
        if let roomId = firebaseManager.activeRoom?.id {
            firebaseManager.removeIndicator(roomId: roomId, indicatorId: id)
        }
        localIndicators.removeValue(forKey: id)
        updateAllTacticalIndicators()
    }
}
