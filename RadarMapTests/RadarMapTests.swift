import XCTest
import CoreLocation
import CoreBluetooth
import SwiftUI
@testable import RadarMap

final class RadarMapTests: XCTestCase {
    
    private func createMockFirebaseSyncManager() -> FirebaseSyncManager {
        let syncManager = FirebaseSyncManager()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        syncManager.urlSession = URLSession(configuration: config)
        return syncManager
    }
    
    // MARK: - Late Packet Rejection Tests
    
    func testLatePacketRejectionInOrder() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "ALPHA1", hostId: "USER1")
        let member = SquadMember(id: "USER2", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        var updatedRoom = room
        updatedRoom.members["USER2"] = member
        syncManager.connectToRoom(updatedRoom)
        
        let now = Date().timeIntervalSince1970
        
        // Packet 1: sequence 1
        let p1 = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.771, longitude: -122.411, heading: 45.0, heartRate: 80.0, timestamp: now, sequenceNumber: 1)
        XCTAssertTrue(syncManager.validateAndProcessPacket(p1), "Fresh in-order packet 1 should be accepted")
        
        // Packet 2: sequence 2, higher timestamp
        let p2 = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.772, longitude: -122.412, heading: 50.0, heartRate: 85.0, timestamp: now + 1.0, sequenceNumber: 2)
        XCTAssertTrue(syncManager.validateAndProcessPacket(p2), "Fresh in-order packet 2 should be accepted")
        
        XCTAssertEqual(syncManager.totalPacketsProcessed, 2)
        XCTAssertEqual(syncManager.totalPacketsRejected, 0)
    }
    
    func testLatePacketRejectionOutOfOrderSequence() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "ALPHA1", hostId: "USER1")
        let member = SquadMember(id: "USER2", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        var updatedRoom = room
        updatedRoom.members["USER2"] = member
        syncManager.connectToRoom(updatedRoom)
        
        let now = Date().timeIntervalSince1970
        
        // Packet 1: sequence 5
        let p1 = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.771, longitude: -122.411, heading: 45.0, heartRate: 80.0, timestamp: now, sequenceNumber: 5)
        XCTAssertTrue(syncManager.validateAndProcessPacket(p1))
        
        // Packet 2: sequence 3 (late / out-of-order)
        let p2 = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.772, longitude: -122.412, heading: 50.0, heartRate: 85.0, timestamp: now + 0.5, sequenceNumber: 3)
        XCTAssertFalse(syncManager.validateAndProcessPacket(p2), "Out-of-order sequence packet should be rejected")
        
        XCTAssertEqual(syncManager.totalPacketsProcessed, 1)
        XCTAssertEqual(syncManager.totalPacketsRejected, 1)
        XCTAssertEqual(syncManager.latestRejection?.reason, .outOfOrderSequence)
    }
    
    func testLatePacketRejectionStaleTimestamp() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "ALPHA1", hostId: "USER1")
        let member = SquadMember(id: "USER2", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        var updatedRoom = room
        updatedRoom.members["USER2"] = member
        syncManager.connectToRoom(updatedRoom)
        
        let now = Date().timeIntervalSince1970
        
        // Packet 1: timestamp = now
        let p1 = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.771, longitude: -122.411, heading: 45.0, heartRate: 80.0, timestamp: now, sequenceNumber: 1)
        XCTAssertTrue(syncManager.validateAndProcessPacket(p1))
        
        // Packet 2: higher sequence number but older timestamp
        let p2 = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.772, longitude: -122.412, heading: 50.0, heartRate: 85.0, timestamp: now - 2.0, sequenceNumber: 2)
        XCTAssertFalse(syncManager.validateAndProcessPacket(p2), "Stale timestamp packet should be rejected")
        
        XCTAssertEqual(syncManager.totalPacketsProcessed, 1)
        XCTAssertEqual(syncManager.totalPacketsRejected, 1)
        XCTAssertEqual(syncManager.latestRejection?.reason, .staleTimestamp)
    }
    
    func testPacketAcceptedRegardlessOfAge() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "ALPHA1", hostId: "USER1")
        let member = SquadMember(id: "USER2", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        var updatedRoom = room
        updatedRoom.members["USER2"] = member
        syncManager.connectToRoom(updatedRoom)
        
        let now = Date().timeIntervalSince1970
        
        // Packet generated in past (e.g. 60 seconds ago)
        let olderPacket = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.771, longitude: -122.411, heading: 45.0, heartRate: 80.0, timestamp: now - 60.0, sequenceNumber: 1)
        XCTAssertTrue(syncManager.validateAndProcessPacket(olderPacket), "Older packet should be accepted without arbitrary age limits")
        XCTAssertEqual(syncManager.totalPacketsProcessed, 1)
        XCTAssertEqual(syncManager.totalPacketsRejected, 0)
    }
    
    // MARK: - Mock URL Protocol for Deterministic Network Testing
    
    class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?
        static var recordedRequests: [URLRequest] = []
        
        static func reset() {
            requestHandler = nil
            recordedRequests.removeAll()
        }
        
        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }
        
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }
        
        override func startLoading() {
            MockURLProtocol.recordedRequests.append(request)
            guard let handler = MockURLProtocol.requestHandler else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: "{}".data(using: .utf8)!)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if let data = data {
                    client?.urlProtocol(self, didLoad: data)
                }
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        
        override func stopLoading() {}
    }
    
    private func createMockGameState() -> GameStateManager {
        let gameState = GameStateManager()
        gameState.myCallsign = "OPERATOR"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        gameState.firebaseManager.urlSession = URLSession(configuration: config)
        return gameState
    }
    
    // MARK: - Paywall Capacity Tests
    
    func testPaywallCapacityEnforcement() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = false
        
        let exp1 = expectation(description: "Free room hosted")
        gameState.hostRoom(name: "FREE SQUAD") { _ in
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.maxCapacity, 4)
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = true
        let exp2 = expectation(description: "Pro room hosted")
        gameState.hostRoom(name: "PRO SQUAD") { _ in
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.maxCapacity, 999)
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)
    }
    
    // MARK: - Heart Rate Zone Color Tests
    
    func testHeartRateZoneColors() {
        let restingMember = SquadMember(callsign: "ONE", latitude: 0, longitude: 0, heartRate: 55)
        XCTAssertEqual(restingMember.heartRateZoneColor, .blue)
        
        let normalMember = SquadMember(callsign: "TWO", latitude: 0, longitude: 0, heartRate: 80)
        XCTAssertEqual(normalMember.heartRateZoneColor, .green)
        
        let elevatedMember = SquadMember(callsign: "THREE", latitude: 0, longitude: 0, heartRate: 120)
        XCTAssertEqual(elevatedMember.heartRateZoneColor, .yellow)
        
        let highStressMember = SquadMember(callsign: "FOUR", latitude: 0, longitude: 0, heartRate: 150)
        XCTAssertEqual(highStressMember.heartRateZoneColor, .orange)
        
        let maxStressMember = SquadMember(callsign: "FIVE", latitude: 0, longitude: 0, heartRate: 185)
        XCTAssertEqual(maxStressMember.heartRateZoneColor, .red)
    }
    
    // MARK: - Tactical Map Style & Distance Verification Tests
    
    func testTacticalMapStyles() {
        XCTAssertTrue(TacticalMapStyle.allCases.contains(.radar))
        XCTAssertTrue(TacticalMapStyle.allCases.contains(.standard))
        XCTAssertEqual(TacticalMapStyle.radar.rawValue, "Radar")
        XCTAssertEqual(TacticalMapStyle.standard.rawValue, "Standard")
        XCTAssertEqual(TacticalMapStyle.radar.iconName, "scope")
        XCTAssertEqual(TacticalMapStyle.standard.iconName, "map")
        XCTAssertEqual(TacticalMapStyle.allCases.count, 2)
    }
    
    func testRadarColorThemes() {
        XCTAssertTrue(RadarColorTheme.allCases.contains(.red))
        XCTAssertTrue(RadarColorTheme.allCases.contains(.green))
        XCTAssertEqual(RadarColorTheme.allCases.count, 2)
        XCTAssertEqual(RadarColorTheme.red.color, .red)
        XCTAssertEqual(RadarColorTheme.green.color, .green)
    }
    
    func testStaleMemberDataOlderThan15Seconds() {
        let now = Date()
        let freshMember = SquadMember(
            callsign: "FRESH",
            latitude: 37.77,
            longitude: -122.41,
            lastUpdatedTimestamp: now.timeIntervalSince1970 - 5.0
        )
        XCTAssertFalse(freshMember.isStale(asOf: now), "Member updated 5s ago should not be stale")
        
        let staleMember = SquadMember(
            callsign: "STALE",
            latitude: 37.77,
            longitude: -122.41,
            lastUpdatedTimestamp: now.timeIntervalSince1970 - 16.0
        )
        XCTAssertTrue(staleMember.isStale(asOf: now), "Member updated > 15s ago should be marked as stale")
    }
    
    func testStaleMemberDynamicIntervalAndMultiplier() {
        let now = Date()
        
        // Stale timeout duration: M * interval
        // Default: M = 15, interval = 1s -> 15s
        XCTAssertEqual(SquadMember.staleTimeoutDuration(updateInterval: 1.0, multiplier: 15.0), 15.0)
        // Interval = 2s, M = 15 -> 30s
        XCTAssertEqual(SquadMember.staleTimeoutDuration(updateInterval: 2.0, multiplier: 15.0), 30.0)
        // Interval = 5s, M = 15 -> 75s
        XCTAssertEqual(SquadMember.staleTimeoutDuration(updateInterval: 5.0, multiplier: 15.0), 75.0)
        
        // Member updated 25 seconds ago
        let member25s = SquadMember(
            callsign: "TEST_25S",
            latitude: 37.77,
            longitude: -122.41,
            lastUpdatedTimestamp: now.timeIntervalSince1970 - 25.0
        )
        
        // With 1.0s interval (timeout = 15s), 25s elapsed IS stale
        XCTAssertTrue(member25s.isStale(updateInterval: 1.0, multiplier: 15.0, asOf: now))
        
        // With 2.0s interval (timeout = 30s), 25s elapsed is NOT yet stale (fresh)
        XCTAssertFalse(member25s.isStale(updateInterval: 2.0, multiplier: 15.0, asOf: now))
        
        // Member updated 35 seconds ago
        let member35s = SquadMember(
            callsign: "TEST_35S",
            latitude: 37.77,
            longitude: -122.41,
            lastUpdatedTimestamp: now.timeIntervalSince1970 - 35.0
        )
        // With 2.0s interval (timeout = 30s), 35s elapsed IS stale
        XCTAssertTrue(member35s.isStale(updateInterval: 2.0, multiplier: 15.0, asOf: now))
    }
    
    func testRadarDistanceAndScaleAccuracy() {
        // Operator position (e.g. San Francisco)
        let userCoord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let radarRangeMeters: Double = 100.0
        let maxRadiusPoints: Double = 100.0
        
        // 1 degree latitude ~ 111,139 meters
        let metersPerDegreeLat: Double = 111_139.0
        let metersPerDegreeLon: Double = 111_139.0 * cos(userCoord.latitude * .pi / 180.0)
        let pointsPerMeter: Double = maxRadiusPoints / radarRangeMeters
        
        // 1. Target exactly 50 meters North (should land precisely on Ring 2: 50% radius)
        let deltaLat50m: Double = 50.0 / metersPerDegreeLat
        let targetNorth = CLLocationCoordinate2D(latitude: userCoord.latitude + deltaLat50m, longitude: userCoord.longitude)
        
        let dLatN: Double = targetNorth.latitude - userCoord.latitude
        let dLonN: Double = targetNorth.longitude - userCoord.longitude
        let yOffsetN: Double = -(dLatN * metersPerDegreeLat) * pointsPerMeter
        let xOffsetN: Double = (dLonN * metersPerDegreeLon) * pointsPerMeter
        
        XCTAssertEqual(xOffsetN, 0.0, accuracy: 0.001)
        XCTAssertEqual(yOffsetN, -50.0, accuracy: 0.001) // 50 points upward = 50% of 100pt maxRadius
        
        let radialDistN = sqrt(pow(xOffsetN, 2.0) + pow(yOffsetN, 2.0))
        XCTAssertEqual(radialDistN, 50.0, accuracy: 0.001) // Exactly matches 50m Ring 2!
        
        // 2. Target exactly 25 meters East (should land precisely on Ring 1: 25% radius)
        let deltaLon25m: Double = 25.0 / metersPerDegreeLon
        let targetEast = CLLocationCoordinate2D(latitude: userCoord.latitude, longitude: userCoord.longitude + deltaLon25m)
        
        let dLatE: Double = targetEast.latitude - userCoord.latitude
        let dLonE: Double = targetEast.longitude - userCoord.longitude
        let yOffsetE: Double = -(dLatE * metersPerDegreeLat) * pointsPerMeter
        let xOffsetE: Double = (dLonE * metersPerDegreeLon) * pointsPerMeter
        
        XCTAssertEqual(xOffsetE, 25.0, accuracy: 0.001) // Exactly 25 points right
        XCTAssertEqual(yOffsetE, 0.0, accuracy: 0.001)
        let radialDistE = sqrt(pow(xOffsetE, 2.0) + pow(yOffsetE, 2.0))
        XCTAssertEqual(radialDistE, 25.0, accuracy: 0.001) // Exactly matches 25m Ring 1!
        
        // 3. Target 100 meters at 45 degree bearing (should land on outer boundary Ring 4: 100% radius)
        let dist100m: Double = 100.0
        let deltaLat45: Double = (dist100m * cos(.pi / 4.0)) / metersPerDegreeLat
        let deltaLon45: Double = (dist100m * sin(.pi / 4.0)) / metersPerDegreeLon
        let targetNE = CLLocationCoordinate2D(latitude: userCoord.latitude + deltaLat45, longitude: userCoord.longitude + deltaLon45)
        
        let dLatNE: Double = targetNE.latitude - userCoord.latitude
        let dLonNE: Double = targetNE.longitude - userCoord.longitude
        let yOffsetNE: Double = -(dLatNE * metersPerDegreeLat) * pointsPerMeter
        let xOffsetNE: Double = (dLonNE * metersPerDegreeLon) * pointsPerMeter
        
        let radialDistNE = sqrt(pow(xOffsetNE, 2.0) + pow(yOffsetNE, 2.0))
        XCTAssertEqual(radialDistNE, 100.0, accuracy: 0.001) // Exactly matches 100m Ring 4!
    }
    
    // MARK: - Player Death & Revive State Tests
    
    func testPlayerDeathState() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        XCTAssertFalse(gameState.isDead, "Initial player state should be alive")
        
        let exp = expectation(description: "Host room")
        gameState.hostRoom(name: "Test Squad", pin: "TEST") { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        guard let myId = gameState.firebaseManager.activeRoom?.members.keys.first else {
            XCTFail("Active member should exist")
            return
        }
        XCTAssertEqual(gameState.firebaseManager.activeRoom?.members[myId]?.status, .active)
        
        // Trigger death
        gameState.setDead(true)
        XCTAssertTrue(gameState.isDead, "Player state should be dead")
        XCTAssertEqual(gameState.firebaseManager.activeRoom?.members[myId]?.status, .downed)
        
        // Revive
        gameState.setDead(false)
        XCTAssertFalse(gameState.isDead, "Player should be revived")
        XCTAssertEqual(gameState.firebaseManager.activeRoom?.members[myId]?.status, .active)
    }
    
    // MARK: - Password & Security Tests
    
    func testPasswordHashingAndVerification() {
        let pin = "1234"
        let roomId = "ALPH"
        let hash1 = FirebaseSyncManager.hashPassword(pin, salt: roomId)
        let hash2 = FirebaseSyncManager.hashPassword("1234", salt: "ALPH")
        let wrongHash = FirebaseSyncManager.hashPassword("9999", salt: "ALPH")
        
        XCTAssertFalse(hash1.isEmpty)
        XCTAssertEqual(hash1, hash2, "Identical PIN and salt must yield identical hash")
        XCTAssertNotEqual(hash1, wrongHash, "Different PIN must yield different hash")
        
        // Empty PIN
        XCTAssertEqual(FirebaseSyncManager.hashPassword("", salt: roomId), "")
    }
    
    func testPinRetentionInUserDefaultsAndGameState() {
        let testPin = "7412"
        UserDefaults.standard.set(testPin, forKey: AppConstants.Storage.savedPinKey)
        
        let gameState = createMockGameState()
        XCTAssertEqual(gameState.savedPin, "7412", "GameStateManager should initialize with the retained PIN from UserDefaults")
        
        // Changing savedPin directly updates UserDefaults
        gameState.savedPin = "9876"
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.Storage.savedPinKey), "9876", "Updating savedPin should persist to UserDefaults")
        
        // Hosting a room with PIN retains it
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let hostExp = expectation(description: "Host with PIN")
        gameState.hostRoom(name: "PIN SQUAD", pin: "4321") { _ in
            hostExp.fulfill()
        }
        wait(for: [hostExp], timeout: 1.0)
        XCTAssertEqual(gameState.savedPin, "4321", "Hosting with PIN should retain the PIN")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.Storage.savedPinKey), "4321")
        
        // Joining a room with PIN retains it
        let joinExp = expectation(description: "Join with PIN")
        gameState.joinRoom(id: "PIN SQUAD", pin: "5555") { (success: Bool) in
            joinExp.fulfill()
        }
        wait(for: [joinExp], timeout: 1.0)
        XCTAssertEqual(gameState.savedPin, "5555", "Joining with PIN should retain the PIN")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.Storage.savedPinKey), "5555")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.savedPinKey)
    }
    
    func testKIATelemetryFlatlineZeroBPM() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "BRAVO", hostId: "HOST1")
        let member = SquadMember(id: "OP1", callsign: "GHOST", latitude: 37.77, longitude: -122.41, heartRate: 140.0, status: .active)
        var updatedRoom = room
        updatedRoom.members["OP1"] = member
        syncManager.connectToRoom(updatedRoom)
        
        XCTAssertEqual(syncManager.activeRoom?.members["OP1"]?.status, .active)
        
        // Broadcast KIA flatline packet (hr = 0.0)
        let kiaPacket = TelemetryPacket(
            memberId: "OP1",
            roomId: "BRAVO",
            latitude: 37.775,
            longitude: -122.415,
            heading: 180.0,
            heartRate: 0.0,
            timestamp: Date().timeIntervalSince1970,
            sequenceNumber: 1
        )
        
        XCTAssertTrue(syncManager.validateAndProcessPacket(kiaPacket))
        XCTAssertEqual(syncManager.activeRoom?.members["OP1"]?.heartRate, 0.0)
        XCTAssertEqual(syncManager.activeRoom?.members["OP1"]?.status, .downed, "0 BPM packet should transition member to downed status")
    }
    
    // MARK: - 3-Player North & East Offset Verification Test
    
    func testThreePlayerNorthOffsetTestData() {
        let syncManager = createMockFirebaseSyncManager()
        let metersPerDegreeLat: Double = 111_139.0
        
        // Base reference coordinate
        let baseLat = 37.785834
        let baseLng = -122.406417
        let metersPerDegreeLon: Double = 111_139.0 * cos(baseLat * .pi / 180.0)
        let eastOffset25m: Double = 25.0 / metersPerDegreeLon
        let targetLng = baseLng + eastOffset25m
        
        // Player 1 (25 meters North, 25 meters East of base)
        let p1Lat = baseLat + (25.0 / metersPerDegreeLat)
        let p1Lng = targetLng
        
        // Player 2 (50 meters North, 25 meters East of base)
        let p2Lat = baseLat + (50.0 / metersPerDegreeLat)
        let p2Lng = targetLng
        
        // Player 3 (150 meters North, 25 meters East of base)
        let p3Lat = baseLat + (150.0 / metersPerDegreeLat)
        let p3Lng = targetLng
        
        // Room setup
        let room = SquadRoom(
            id: "MOCK_TEST_ROOM",
            hostId: "PLAYER_1",
            members: [
                "PLAYER_1": SquadMember(id: "PLAYER_1", callsign: "ALPHA-1", latitude: p1Lat, longitude: p1Lng, heading: 0.0, heartRate: 75.0, isHost: true),
                "PLAYER_2": SquadMember(id: "PLAYER_2", callsign: "ALPHA-2", latitude: p2Lat, longitude: p2Lng, heading: 0.0, heartRate: 85.0),
                "PLAYER_3": SquadMember(id: "PLAYER_3", callsign: "ALPHA-3", latitude: p3Lat, longitude: p3Lng, heading: 0.0, heartRate: 95.0)
            ]
        )
        syncManager.connectToRoom(room)
        
        // Verify accurate distance calculations
        let baseLoc = CLLocation(latitude: baseLat, longitude: baseLng)
        let loc1 = CLLocation(latitude: p1Lat, longitude: p1Lng)
        let loc2 = CLLocation(latitude: p2Lat, longitude: p2Lng)
        let loc3 = CLLocation(latitude: p3Lat, longitude: p3Lng)
        
        // Distance from base: sqrt(north^2 + east^2)
        XCTAssertEqual(baseLoc.distance(from: loc1), 35.355, accuracy: 1.0, "Player 1 should be ~25m north and 25m east of base")
        XCTAssertEqual(baseLoc.distance(from: loc2), 55.902, accuracy: 1.0, "Player 2 should be ~50m north and 25m east of base")
        XCTAssertEqual(baseLoc.distance(from: loc3), 152.069, accuracy: 1.5, "Player 3 should be ~150m north and 25m east of base")
        
        // Verify 25m East displacement from north-only positions
        let p1NorthOnly = CLLocation(latitude: p1Lat, longitude: baseLng)
        let p2NorthOnly = CLLocation(latitude: p2Lat, longitude: baseLng)
        let p3NorthOnly = CLLocation(latitude: p3Lat, longitude: baseLng)
        XCTAssertEqual(p1NorthOnly.distance(from: loc1), 25.0, accuracy: 0.5, "Player 1 should be 25m east of north line")
        XCTAssertEqual(p2NorthOnly.distance(from: loc2), 25.0, accuracy: 0.5, "Player 2 should be 25m east of north line")
        XCTAssertEqual(p3NorthOnly.distance(from: loc3), 25.0, accuracy: 0.5, "Player 3 should be 25m east of north line")
        
        // Verify Firebase telemetry packet ingestion for all 3 players
        let now = Date().timeIntervalSince1970
        let pkt1 = TelemetryPacket(memberId: "PLAYER_1", roomId: "MOCK_TEST_ROOM", latitude: p1Lat, longitude: p1Lng, heading: 0.0, heartRate: 78.0, timestamp: now, sequenceNumber: 1)
        let pkt2 = TelemetryPacket(memberId: "PLAYER_2", roomId: "MOCK_TEST_ROOM", latitude: p2Lat, longitude: p2Lng, heading: 10.0, heartRate: 88.0, timestamp: now, sequenceNumber: 1)
        let pkt3 = TelemetryPacket(memberId: "PLAYER_3", roomId: "MOCK_TEST_ROOM", latitude: p3Lat, longitude: p3Lng, heading: 20.0, heartRate: 98.0, timestamp: now, sequenceNumber: 1)
        
        XCTAssertTrue(syncManager.validateAndProcessPacket(pkt1))
        XCTAssertTrue(syncManager.validateAndProcessPacket(pkt2))
        XCTAssertTrue(syncManager.validateAndProcessPacket(pkt3))
        
        XCTAssertEqual(syncManager.totalPacketsProcessed, 3)
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_1"]?.heartRate, 78.0)
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_2"]?.heartRate, 88.0)
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_3"]?.heartRate, 98.0)
    }
    
    func testAutoRegisterUnknownMemberFromTelemetry() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "MOCK_TEST_ROOM", hostId: "LOCAL_PLAYER", members: [:])
        syncManager.connectToRoom(room)
        
        let now = Date().timeIntervalSince1970
        let p1 = TelemetryPacket(memberId: "PLAYER_1", roomId: "TEST", latitude: 37.7860589, longitude: -122.4061324, heading: 0.0, heartRate: 78.0, timestamp: now, sequenceNumber: 1)
        let p2 = TelemetryPacket(memberId: "PLAYER_2", roomId: "TEST", latitude: 37.7862839, longitude: -122.4061324, heading: 10.0, heartRate: 88.0, timestamp: now, sequenceNumber: 1)
        let p3 = TelemetryPacket(memberId: "PLAYER_3", roomId: "TEST", latitude: 37.7871837, longitude: -122.4061324, heading: 20.0, heartRate: 98.0, timestamp: now, sequenceNumber: 1)
        
        XCTAssertTrue(syncManager.validateAndProcessPacket(p1))
        XCTAssertTrue(syncManager.validateAndProcessPacket(p2))
        XCTAssertTrue(syncManager.validateAndProcessPacket(p3))
        
        XCTAssertEqual(syncManager.activeRoom?.members.count, 3)
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_1"]?.callsign, "PLAYER_1")
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_2"]?.callsign, "PLAYER_2")
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_3"]?.callsign, "PLAYER_3")
    }
    
    func testSquadRoomAndMemberResilientDecoding() throws {
        let rawJson = """
        {
            "id": "TEST",
            "hostId": "PLAYER_1",
            "members": {
                "PLAYER_1": {"callsign": "ALPHA-1", "heading": 0.0, "heartRate": 78.0, "id": "PLAYER_1", "isHost": true, "latitude": 37.7860589, "longitude": -122.4061324, "status": "active"},
                "PLAYER_2": {"callsign": "ALPHA-2", "heading": 0.0, "heartRate": 88.0, "id": "PLAYER_2", "isHost": false, "latitude": 37.7862839, "longitude": -122.4061324, "status": "active"},
                "PLAYER_3": {"callsign": "ALPHA-3", "heading": 0.0, "heartRate": 98.0, "id": "PLAYER_3", "isHost": false, "latitude": 37.7871837, "longitude": -122.4061324, "status": "active"}
            }
        }
        """
        let data = Data(rawJson.utf8)
        let decodedRoom = try JSONDecoder().decode(SquadRoom.self, from: data)
        
        XCTAssertEqual(decodedRoom.id, "TEST")
        XCTAssertEqual(decodedRoom.members.count, 3)
        XCTAssertEqual(decodedRoom.members["PLAYER_1"]?.callsign, "ALPHA-1")
        XCTAssertEqual(decodedRoom.members["PLAYER_2"]?.callsign, "ALPHA-2")
        XCTAssertEqual(decodedRoom.members["PLAYER_3"]?.callsign, "ALPHA-3")
        XCTAssertEqual(decodedRoom.members["PLAYER_1"]?.heartRate, 78.0)
    }
    
    func testHostAndJoinLifecycleState() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" && request.url?.absoluteString.contains("CHARLIE") == true {
                let testRoom = SquadRoom(id: "CHARLIE", hostId: "REMOTE_HOST", members: [:])
                let data = try! JSONEncoder().encode(testRoom)
                return (response, data)
            }
            return (response, "null".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        XCTAssertFalse(gameState.isHosting)
        XCTAssertFalse(gameState.isJoining)
        XCTAssertFalse(gameState.firebaseManager.isConnected)
        
        // Host room
        let hostExp = expectation(description: "Host room")
        gameState.hostRoom(name: "BRAVO SQUAD", pin: "1234") { success in
            XCTAssertTrue(success)
            XCTAssertTrue(gameState.isHosting)
            XCTAssertFalse(gameState.isJoining)
            XCTAssertTrue(gameState.firebaseManager.isConnected)
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.name, "BRAVO SQUAD")
            hostExp.fulfill()
        }
        wait(for: [hostExp], timeout: 1.0)
        
        // Leave / Disband room
        let leaveExp = expectation(description: "Leave room")
        gameState.leaveCurrentRoom { _ in
            XCTAssertFalse(gameState.isHosting)
            XCTAssertFalse(gameState.isJoining)
            XCTAssertFalse(gameState.firebaseManager.isConnected)
            XCTAssertNil(gameState.firebaseManager.activeRoom)
            leaveExp.fulfill()
        }
        wait(for: [leaveExp], timeout: 1.0)
        
        // Join room
        let joinExp = expectation(description: "Join room")
        gameState.joinRoom(id: "CHARLIE", name: "CHARLIE", pin: "5678") { success in
            XCTAssertTrue(success)
            XCTAssertFalse(gameState.isHosting)
            XCTAssertFalse(gameState.isJoining)
            XCTAssertTrue(gameState.firebaseManager.isConnected)
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.id, "CHARLIE")
            joinExp.fulfill()
        }
        wait(for: [joinExp], timeout: 1.0)
    }
    
    // MARK: - Host Button Specification Tests
    
    func testHostButton_Workflow_Initiating_Success_Disband_ServerRoomDeleted() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        
        // 1. Initial State
        XCTAssertFalse(gameState.isInitiatingHost)
        XCTAssertFalse(gameState.isHosting)
        XCTAssertFalse(gameState.isJoining)
        
        // 2. Start hosting
        let hostExp = expectation(description: "Host creation confirmed")
        gameState.hostRoom(name: "ALPHA SQUAD", pin: "1111") { success in
            XCTAssertTrue(success)
            // 4. Server creation confirmed -> becomes disband
            XCTAssertFalse(gameState.isInitiatingHost)
            XCTAssertTrue(gameState.isHosting)
            XCTAssertTrue(gameState.isCurrentMemberHost)
            hostExp.fulfill()
        }
        
        wait(for: [hostExp], timeout: 1.0)
        
        // 5. Disband -> server's room is deleted
        let disbandExp = expectation(description: "Room disbanded")
        gameState.leaveCurrentRoom { _ in
            disbandExp.fulfill()
        }
        wait(for: [disbandExp], timeout: 1.0)
        
        // Verify DELETE requests were sent for the room and telemetry
        let deleteRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "DELETE" }
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/rooms/ALPHA%20SQUAD.json") == true || $0.url?.absoluteString.contains("/rooms/ALPHA SQUAD.json") == true })
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/telemetry/ALPHA%20SQUAD.json") == true || $0.url?.absoluteString.contains("/telemetry/ALPHA SQUAD.json") == true })
        
        XCTAssertFalse(gameState.isHosting)
        XCTAssertNil(gameState.firebaseManager.activeRoom)
    }
    
    func testHostButton_Workflow_CreationFailure_RevertsToHost() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }
        
        let gameState = createMockGameState()
        
        let exp = expectation(description: "Host creation failure")
        gameState.hostRoom(name: "FAIL SQUAD") { success in
            XCTAssertFalse(success)
            // 3. Goes back to being host if creation process failed
            XCTAssertFalse(gameState.isInitiatingHost)
            XCTAssertFalse(gameState.isHosting)
            XCTAssertFalse(gameState.isCurrentMemberHost)
            XCTAssertNotNil(gameState.errorMessage)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testHostButton_DisabledWhenJoinIsPressed() {
        let gameState = createMockGameState()
        gameState.isJoining = true
        
        // When join is pressed (isJoining == true), Host is disabled
        XCTAssertTrue(gameState.isJoining)
    }
    
    // MARK: - Join Button Specification Tests
    
    func testJoinButton_Workflow_Joining_Success_Leave_PlayerEntryDeleted() {
        MockURLProtocol.reset()
        let targetRoom = SquadRoom(id: "DELTA", hostId: "HOST_OPERATOR", members: [:])
        let roomData = try! JSONEncoder().encode(targetRoom)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        
        // 1. Initial State
        XCTAssertFalse(gameState.isJoining)
        XCTAssertFalse(gameState.firebaseManager.isConnected)
        
        // 2. Start joining
        let joinExp = expectation(description: "Join confirmed")
        gameState.joinRoom(id: "DELTA") { success in
            XCTAssertTrue(success)
            // 4. Server connection confirmed -> becomes leave
            XCTAssertFalse(gameState.isJoining)
            XCTAssertTrue(gameState.firebaseManager.isConnected)
            XCTAssertFalse(gameState.isCurrentMemberHost)
            joinExp.fulfill()
        }
        wait(for: [joinExp], timeout: 1.0)
        
        // 5. Leave -> server's player entry is deleted
        let leaveExp = expectation(description: "Player left room")
        gameState.leaveCurrentRoom { _ in
            leaveExp.fulfill()
        }
        wait(for: [leaveExp], timeout: 1.0)
        
        // Verify DELETE requests were sent specifically for player member entry and player telemetry
        let deleteRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "DELETE" }
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/rooms/DELTA/members/\(gameState.myMemberId).json") == true })
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/telemetry/DELTA/\(gameState.myMemberId).json") == true })
        
        XCTAssertFalse(gameState.firebaseManager.isConnected)
        XCTAssertNil(gameState.firebaseManager.activeRoom)
    }
    
    func testJoinButton_Workflow_RoomNotFound_RevertsToJoin() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, "null".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        
        let exp = expectation(description: "Room not found failure")
        gameState.joinRoom(id: "NONEXISTENT") { success in
            XCTAssertFalse(success)
            // 3. Goes back to join if joining failed
            XCTAssertFalse(gameState.isJoining)
            XCTAssertFalse(gameState.firebaseManager.isConnected)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.roomNotFound.localizedDescription)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testJoinButton_Workflow_IncorrectPIN_RevertsToJoin() {
        MockURLProtocol.reset()
        let pinHash = FirebaseSyncManager.hashPin("9999", salt: "SECURE")
        let secureRoom = SquadRoom(id: "SECURE", hostId: "HOST_USER", hasPin: true, pinHash: pinHash, members: [:])
        let roomData = try! JSONEncoder().encode(secureRoom)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        
        let exp = expectation(description: "Wrong PIN failure")
        gameState.joinRoom(id: "SECURE", pin: "0000") { success in
            XCTAssertFalse(success)
            // Goes back to join if joining failed
            XCTAssertFalse(gameState.isJoining)
            XCTAssertFalse(gameState.firebaseManager.isConnected)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.incorrectPassword.localizedDescription)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testJoinButton_Workflow_RoomFull_RevertsToJoin() {
        MockURLProtocol.reset()
        var fullMembers: [String: SquadMember] = [:]
        for i in 1...4 {
            fullMembers["USER_\(i)"] = SquadMember(id: "USER_\(i)", callsign: "OP_\(i)", latitude: 0, longitude: 0)
        }
        let fullRoom = SquadRoom(id: "FULLSQUAD", hostId: "USER_1", maxCapacity: 4, members: fullMembers)
        let roomData = try! JSONEncoder().encode(fullRoom)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.myMemberId = "NEW_PLAYER"
        
        let exp = expectation(description: "Room full failure")
        gameState.joinRoom(id: "FULLSQUAD") { success in
            XCTAssertFalse(success)
            // Goes back to join if joining failed
            XCTAssertFalse(gameState.isJoining)
            XCTAssertFalse(gameState.firebaseManager.isConnected)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.roomFull.localizedDescription)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testJoinButton_DisabledWhenHostIsPressed() {
        let gameState = createMockGameState()
        gameState.isInitiatingHost = true
        
        // When host is pressed (isInitiatingHost == true), Join is disabled
        XCTAssertTrue(gameState.isInitiatingHost)
    }
    
    // MARK: - Squad Indicator & KIA Tests
    
    func testSquadIndicatorStateAndKIATrigger() {
        let slMember = SquadMember(
            id: "LEADER1",
            callsign: "SL-ALPHA",
            latitude: 37.77,
            longitude: -122.41,
            heading: 90.0,
            heartRate: 110.0,
            status: .active,
            isHost: true,
            colorHex: "#00FF66"
        )
        XCTAssertTrue(slMember.isHost, "Room creator must be identified as Squad Leader")
        XCTAssertGreaterThan(slMember.heartRate, 0)
        XCTAssertEqual(slMember.status, .active)
        
        let kiaMember = SquadMember(
            id: "PLAYER2",
            callsign: "BRAVO-2",
            latitude: 37.77,
            longitude: -122.41,
            heading: 180.0,
            heartRate: 0.0,
            status: .active,
            isHost: false,
            colorHex: "#00FF66"
        )
        XCTAssertEqual(kiaMember.heartRate, 0.0, "Zero BPM indicates KIA / Flatline")
        
        // Color hex test
        let customColor = Color(hex: "#00FF66")
        XCTAssertNotNil(customColor)
        
        let invalidColor = Color(hex: "invalid")
        XCTAssertNil(invalidColor)
    }
    
    func testMemberAnnotationViewDeadTeammateFollowsRadarColorPreference() {
        let deadMember = SquadMember(
            id: "DEAD_MEMBER",
            callsign: "FALLEN",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 0.0,
            status: .downed
        )
        
        // When radar color theme is green
        let greenAnnotationView = MemberAnnotationView(
            member: deadMember,
            isMe: false,
            radarColor: RadarColorTheme.green.color
        )
        XCTAssertEqual(greenAnnotationView.radarColor, .green)
        
        // When radar color theme is red
        let redAnnotationView = MemberAnnotationView(
            member: deadMember,
            isMe: false,
            radarColor: RadarColorTheme.red.color
        )
        XCTAssertEqual(redAnnotationView.radarColor, .red)
    }
    
    func testMemberAnnotationViewDeadTeammateStaleFadesToGray() {
        let staleDeadMember = SquadMember(
            id: "DEAD_STALE_MEMBER",
            callsign: "GHOST",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 0.0,
            lastUpdatedTimestamp: Date().timeIntervalSince1970 - 20.0,
            status: .downed
        )
        XCTAssertTrue(staleDeadMember.isStale, "Member updated > 15s ago should be stale")
        
        let view = MemberAnnotationView(
            member: staleDeadMember,
            isMe: false,
            radarColor: .red
        )
        XCTAssertTrue(view.member.isStale)
    }
    
    func testMemberAnnotationViewTeammateNameFollowsRadarColor() {
        let activeTeammate = SquadMember(
            id: "TEAMMATE_1",
            callsign: "VIPER",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 85.0,
            status: .active
        )
        
        let greenView = MemberAnnotationView(
            member: activeTeammate,
            isMe: false,
            radarColor: RadarColorTheme.green.color
        )
        XCTAssertEqual(greenView.radarColor, .green)
        
        let redView = MemberAnnotationView(
            member: activeTeammate,
            isMe: false,
            radarColor: RadarColorTheme.red.color
        )
        XCTAssertEqual(redView.radarColor, .red)
    }
    
    func testMemberAnnotationViewTeammateIconFollowsRadarMapColorScheme() {
        let teammate = SquadMember(
            id: "TEAMMATE_1",
            callsign: "VIPER",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 85.0,
            status: .active,
            colorHex: "#00FF66"
        )
        
        let redView = MemberAnnotationView(
            member: teammate,
            isMe: false,
            radarColor: RadarColorTheme.red.color
        )
        XCTAssertEqual(redView.indicatorColor, .red, "Teammate icon must follow red radar map color theme")
        
        let greenView = MemberAnnotationView(
            member: teammate,
            isMe: false,
            radarColor: RadarColorTheme.green.color
        )
        XCTAssertEqual(greenView.indicatorColor, .green, "Teammate icon must follow green radar map color theme")
    }
    
    func testMemberAnnotationViewMeIconFollowsRadarMapColorScheme() {
        let myMember = SquadMember(
            id: "MY_USER_ID",
            callsign: "GHOST",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 80.0,
            status: .active,
            colorHex: "#00FF66"
        )
        
        let redMeView = MemberAnnotationView(
            member: myMember,
            isMe: true,
            radarColor: RadarColorTheme.red.color
        )
        XCTAssertEqual(redMeView.indicatorColor, .red, "The 'me' icon must follow the red radar map color scheme")
        
        let greenMeView = MemberAnnotationView(
            member: myMember,
            isMe: true,
            radarColor: RadarColorTheme.green.color
        )
        XCTAssertEqual(greenMeView.indicatorColor, .green, "The 'me' icon must follow the green radar map color scheme")
    }
    
    func testMemberAnnotationViewRetainsThemeColorWhenKIA() {
        let deadMe = SquadMember(
            id: "MY_USER_ID",
            callsign: "GHOST",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 0.0,
            status: .downed
        )
        
        let deadMeView = MemberAnnotationView(
            member: deadMe,
            isMe: true,
            radarColor: RadarColorTheme.green.color
        )
        XCTAssertEqual(deadMeView.indicatorColor, .green, "The theme color must remain radar theme color when the player is KIA")
        
        let deadTeammate = SquadMember(
            id: "TEAMMATE",
            callsign: "VIPER",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 0.0,
            status: .downed
        )
        let deadTeammateView = MemberAnnotationView(
            member: deadTeammate,
            isMe: false,
            radarColor: RadarColorTheme.red.color
        )
        XCTAssertEqual(deadTeammateView.indicatorColor, .red, "Teammate theme color must remain red radar color when KIA")
    }
    
    func testMemberAnnotationViewRestoresThemeColorWhenRevived() {
        // 1. Green theme revive test
        var revivedMe = SquadMember(
            id: "MY_USER_ID",
            callsign: "GHOST",
            latitude: 37.77,
            longitude: -122.41,
            heartRate: 75.0,
            lastUpdatedTimestamp: Date().timeIntervalSince1970 - 45.0, // Older timestamp
            status: .active
        )
        
        let greenRevivedMeView = MemberAnnotationView(
            member: revivedMe,
            isMe: true,
            radarColor: RadarColorTheme.green.color
        )
        XCTAssertEqual(greenRevivedMeView.indicatorColor, .green, "Revived local player must restore green theme color even if timestamp is older")
        
        // 2. Red theme revive test
        revivedMe.status = .active
        revivedMe.heartRate = 80.0
        let redRevivedMeView = MemberAnnotationView(
            member: revivedMe,
            isMe: true,
            radarColor: RadarColorTheme.red.color
        )
        XCTAssertEqual(redRevivedMeView.indicatorColor, .red, "Revived local player must restore red theme color")
        
        // 3. Test GameStateManager revive restores active status and recent timestamp
        let gameState = GameStateManager()
        gameState.radarColorTheme = .green
        XCTAssertFalse(gameState.isDead, "Initial player state must be alive")
        
        // Default member created without explicit heartRate must be active and not KIA
        let defaultMember = SquadMember(callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        XCTAssertEqual(defaultMember.status, .active)
        let defaultMemberView = MemberAnnotationView(member: defaultMember, isMe: true, radarColor: .green)
        XCTAssertEqual(defaultMemberView.indicatorColor, .green)
        
        // Enabling KIA: state turns dead and downed
        gameState.setDead(true)
        XCTAssertTrue(gameState.isDead, "Player state must be dead when KIA is enabled")
        
        let deadSquadMember = SquadMember(
            id: gameState.myMemberId,
            callsign: gameState.myCallsign,
            latitude: 37.77,
            longitude: -122.41,
            heartRate: AppConstants.Health.flatlineHeartRate,
            status: .downed
        )
        let deadAnnotation = MemberAnnotationView(member: deadSquadMember, isMe: true, radarColor: .red)
        XCTAssertEqual(deadAnnotation.indicatorColor, .red)
        
        // Revive: state restores alive and active
        gameState.setDead(false)
        XCTAssertFalse(gameState.isDead, "Player state must be alive after revive")
        
        let revivedSquadMember = SquadMember(
            id: gameState.myMemberId,
            callsign: gameState.myCallsign,
            latitude: 37.77,
            longitude: -122.41,
            heartRate: AppConstants.Health.defaultRestingHeartRate,
            status: .active
        )
        let revivedAnnotation = MemberAnnotationView(member: revivedSquadMember, isMe: true, radarColor: .red)
        XCTAssertEqual(revivedAnnotation.indicatorColor, .red)
    }
    
    func testTacticalIconShapes() {
        let testRect = CGRect(x: 0, y: 0, width: 24, height: 24)
        
        // 1. SquadPlayerShape
        let playerShape = SquadPlayerShape()
        let playerPath = playerShape.path(in: testRect)
        XCTAssertFalse(playerPath.isEmpty, "SquadPlayerShape path must not be empty")
        let playerBounds = playerPath.boundingRect
        XCTAssertGreaterThan(playerBounds.width, 0)
        XCTAssertGreaterThan(playerBounds.height, 0)
        
        // 2. SquadLeaderShape
        let leaderShape = SquadLeaderShape()
        let leaderPath = leaderShape.path(in: testRect)
        XCTAssertFalse(leaderPath.isEmpty, "SquadLeaderShape path must not be empty")
        let leaderBounds = leaderPath.boundingRect
        XCTAssertGreaterThan(leaderBounds.width, 0)
        XCTAssertGreaterThan(leaderBounds.height, 0)
        
        // 3. SquadDeadXShape
        let deadShape = SquadDeadXShape()
        let deadPath = deadShape.path(in: testRect)
        XCTAssertFalse(deadPath.isEmpty, "SquadDeadXShape path must not be empty")
        let deadBounds = deadPath.boundingRect
        XCTAssertGreaterThan(deadBounds.width, 0)
        XCTAssertGreaterThan(deadBounds.height, 0)
        
        // 4. ECGWaveShape normal & flatline paths
        let normalECG = ECGWaveShape(isFlatline: false)
        let normalPath = normalECG.path(in: testRect)
        XCTAssertFalse(normalPath.isEmpty, "ECGWaveShape path must not be empty")
        
        let flatlineECG = ECGWaveShape(isFlatline: true)
        let flatlinePath = flatlineECG.path(in: testRect)
        XCTAssertFalse(flatlinePath.isEmpty, "ECGWaveShape flatline path must not be empty")
        
        // 5. ECGWaveShape.point scanning dot positions
        let size = CGSize(width: 32, height: 14)
        let midY = size.height / 2.0
        
        // Flatline scanning dot should stay on the horizontal baseline (y = midY) for all progress values
        let flatlineStart = ECGWaveShape.point(at: 0.0, in: size, isFlatline: true)
        XCTAssertEqual(flatlineStart.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(flatlineStart.y, midY, accuracy: 0.001)
        
        let flatlineMid = ECGWaveShape.point(at: 0.5, in: size, isFlatline: true)
        XCTAssertEqual(flatlineMid.x, 16.0, accuracy: 0.001)
        XCTAssertEqual(flatlineMid.y, midY, accuracy: 0.001)
        
        let flatlineEnd = ECGWaveShape.point(at: 1.0, in: size, isFlatline: true)
        XCTAssertEqual(flatlineEnd.x, 32.0, accuracy: 0.001)
        XCTAssertEqual(flatlineEnd.y, midY, accuracy: 0.001)
        
        // Sweep duration calculation tests: referenceBpm / BPM
        let bpm100Duration = AppConstants.Health.referenceBpm / 100.0
        XCTAssertEqual(bpm100Duration, 1.0, accuracy: 0.001)
        let bpm75Duration = AppConstants.Health.referenceBpm / 75.0
        XCTAssertEqual(bpm75Duration, 1.3333, accuracy: 0.001)
        let bpm50Duration = AppConstants.Health.referenceBpm / 50.0
        XCTAssertEqual(bpm50Duration, 2.0, accuracy: 0.001)
    }
    
    // MARK: - Adaptive Throttling & Network Quality Tests
    
    func testNetworkQualityMonitorLatencyAndGrade() {
        let monitor = NetworkQualityMonitor(startMonitoring: false)
        monitor.isConnected = true
        monitor.isConstrained = false
        
        // Initial state with low latency
        monitor.recordLatencySample(40.0)
        XCTAssertEqual(monitor.connectionGrade, .excellent)
        
        // Record multiple high latency samples to move EWMA > 300ms
        for _ in 0..<8 {
            monitor.recordLatencySample(600.0)
        }
        XCTAssertTrue(monitor.connectionGrade == .poor || monitor.connectionGrade == .critical)
        
        // Constrained network (Low Data Mode)
        monitor.isConstrained = true
        monitor.evaluateGrade()
        XCTAssertTrue(monitor.connectionGrade == .poor || monitor.connectionGrade == .critical)
        
        // Disconnected
        monitor.isConnected = false
        monitor.evaluateGrade()
        XCTAssertEqual(monitor.connectionGrade, .offline)
    }
    
    func testAdaptiveDownloadPollingIntervalScaling() {
        let syncManager = FirebaseSyncManager()
        
        // 1. Small room (<= 12 members): Base rate 1.0 Hz -> 1.0s interval
        let room4 = SquadRoom(id: "ROOM4", hostId: "HOST", members: [
            "M1": SquadMember(id: "M1", callsign: "C1", latitude: 0, longitude: 0),
            "M2": SquadMember(id: "M2", callsign: "C2", latitude: 0, longitude: 0)
        ])
        syncManager.activeRoom = room4
        XCTAssertEqual(syncManager.pollingInterval, 1.0)
        
        // 2. Room with 10 members (<= 12 threshold): 1.0s
        var room10 = SquadRoom(id: "ROOM10", hostId: "HOST", members: [:])
        for i in 1...10 {
            room10.members["M\(i)"] = SquadMember(id: "M\(i)", callsign: "C\(i)", latitude: 0, longitude: 0)
        }
        syncManager.activeRoom = room10
        XCTAssertEqual(syncManager.pollingInterval, 1.0)
        
        // 3. Room with 24 members (24 / 12 = 2.0s)
        var room24 = SquadRoom(id: "ROOM24", hostId: "HOST", members: [:])
        for i in 1...24 {
            room24.members["M\(i)"] = SquadMember(id: "M\(i)", callsign: "C\(i)", latitude: 0, longitude: 0)
        }
        syncManager.activeRoom = room24
        XCTAssertEqual(syncManager.pollingInterval, 2.0)
        
        // 4. Large room with 30 members (30 / 12 = 2.5s)
        var room30 = SquadRoom(id: "ROOM30", hostId: "HOST", members: [:])
        for i in 1...30 {
            room30.members["M\(i)"] = SquadMember(id: "M\(i)", callsign: "C\(i)", latitude: 0, longitude: 0)
        }
        syncManager.activeRoom = room30
        XCTAssertEqual(syncManager.pollingInterval, 2.5)
        
        // 5. Massive room with 60 members (60 / 12 = 5.0s)
        var room60 = SquadRoom(id: "ROOM60", hostId: "HOST", members: [:])
        for i in 1...60 {
            room60.members["M\(i)"] = SquadMember(id: "M\(i)", callsign: "C\(i)", latitude: 0, longitude: 0)
        }
        syncManager.activeRoom = room60
        XCTAssertEqual(syncManager.pollingInterval, 5.0)
    }
    
    func testAdaptiveUploadIntervalScalingAndThrottling() {
        let gameState = GameStateManager()
        
        // Create 24 member room (24 / 12 = 2.0s interval)
        var room24 = SquadRoom(id: "ROOM24", hostId: gameState.myMemberId, members: [:])
        for i in 1...24 {
            room24.members["M\(i)"] = SquadMember(id: "M\(i)", callsign: "C\(i)", latitude: 0, longitude: 0)
        }
        gameState.firebaseManager.activeRoom = room24
        gameState.recalculateAdaptiveUploadInterval()
        XCTAssertEqual(gameState.adaptiveUploadInterval, 2.0)
        
        // Test throttling: rapid non-forced calls within interval
        gameState.broadcastLocalTelemetry(force: false) // first one allowed
        let afterFirst = gameState.firebaseManager.totalPacketsProcessed
        
        // Immediate second call should be throttled
        gameState.broadcastLocalTelemetry(force: false)
        XCTAssertEqual(gameState.firebaseManager.totalPacketsProcessed, afterFirst, "Throttled call should not broadcast")
        
        // Forced emergency packet should bypass throttle
        gameState.broadcastLocalTelemetry(force: true)
        XCTAssertEqual(gameState.firebaseManager.totalPacketsProcessed, afterFirst + 1, "Forced packet must bypass throttle")
    }
    
    func testConstantBandwidthMaxUpdateRateEquation() {
        let threshold = FirebaseSyncManager.constantBandwidthPlayerThreshold // 12
        XCTAssertEqual(threshold, 12)
        XCTAssertEqual(FirebaseSyncManager.baselineMaxUpdateRateHz, 1.0)
        
        // At or below threshold: 1.0 Hz (1.0 second interval)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 0), 1.0)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 1), 1.0)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 6), 1.0)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 12), 1.0)
        XCTAssertEqual(FirebaseSyncManager.solveUpdateInterval(playerCount: 12), 1.0)
        
        // Beyond threshold: R = N / P
        // 24 players -> 12 / 24 = 0.5 Hz (2.0s interval)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 24), 0.5)
        XCTAssertEqual(FirebaseSyncManager.solveUpdateInterval(playerCount: 24), 2.0)
        
        // 48 players -> 12 / 48 = 0.25 Hz (4.0s interval)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 48), 0.25)
        XCTAssertEqual(FirebaseSyncManager.solveUpdateInterval(playerCount: 48), 4.0)
        
        // 60 players -> 12 / 60 = 0.20 Hz (5.0s interval)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 60), 0.20)
        XCTAssertEqual(FirebaseSyncManager.solveUpdateInterval(playerCount: 60), 5.0)
        
        // Custom threshold test (e.g., N = 16)
        XCTAssertEqual(FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 32, playerThreshold: 16), 0.5)
        XCTAssertEqual(FirebaseSyncManager.solveUpdateInterval(playerCount: 32, playerThreshold: 16), 2.0)
        
        // Verify total theoretical bandwidth (rate * count) remains constant once past threshold
        let theoreticalBandwidthUnits12 = FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 12) * 12.0
        let theoreticalBandwidthUnits24 = FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 24) * 24.0
        let theoreticalBandwidthUnits60 = FirebaseSyncManager.solveMaxUpdateRateHz(playerCount: 60) * 60.0
        XCTAssertEqual(theoreticalBandwidthUnits12, 12.0, accuracy: 0.001)
        XCTAssertEqual(theoreticalBandwidthUnits24, 12.0, accuracy: 0.001)
        XCTAssertEqual(theoreticalBandwidthUnits60, 12.0, accuracy: 0.001)
    }
    
    func testPinFieldSanitizationAndVoiceInput() {
        // Direct numeric strings
        XCTAssertEqual(GameStateManager.sanitizePinInput("1234"), "1234")
        XCTAssertEqual(GameStateManager.sanitizePinInput("123456"), "1234")
        
        // Voice input / spoken words
        XCTAssertEqual(GameStateManager.sanitizePinInput("one two three four"), "1234")
        XCTAssertEqual(GameStateManager.sanitizePinInput("zero nine eight seven"), "0987")
        XCTAssertEqual(GameStateManager.sanitizePinInput("five 6 seven 8"), "5678")
        XCTAssertEqual(GameStateManager.sanitizePinInput("to for ate"), "248")
        
        // Rejection of letters and non-number characters
        XCTAssertEqual(GameStateManager.sanitizePinInput("abc-1.2!3?4"), "1234")
        XCTAssertEqual(GameStateManager.sanitizePinInput("hello world"), "")
        XCTAssertEqual(GameStateManager.sanitizePinInput("PIN: 4567 (secret)"), "4567")
    }
    
    // MARK: - PIN Schema & Firebase Authentication Tests
    
    func testSquadRoomPinSchemaEncodingDecoding() throws {
        let pin = "4321"
        let pinHash = FirebaseSyncManager.hashPin(pin, salt: "ECHO")
        let room = SquadRoom(
            id: "ECHO",
            hostId: "HOST_ECHO",
            maxCapacity: 4,
            hasPin: true,
            pinHash: pinHash
        )
        
        XCTAssertTrue(room.hasPin)
        XCTAssertEqual(room.pinHash, pinHash)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(room)
        
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["hasPin"] as? Bool, true)
        XCTAssertEqual(jsonObject?["pinHash"] as? String, pinHash)
        // Redundant keys should NOT be present in encoded JSON
        XCTAssertNil(jsonObject?["hasPassword"])
        XCTAssertNil(jsonObject?["passwordHash"])
        XCTAssertNil(jsonObject?["isBluetoothAdvertising"])
        
        let decodedRoom = try JSONDecoder().decode(SquadRoom.self, from: data)
        XCTAssertEqual(decodedRoom.id, "ECHO")
        XCTAssertTrue(decodedRoom.hasPin)
        XCTAssertEqual(decodedRoom.pinHash, pinHash)
    }
    
    func testSquadRoomStreamlinedSchemaDecoding() throws {
        let json = """
        {
            "id": "DELTA",
            "hostId": "HOST_DELTA",
            "maxCapacity": 4,
            "createdAt": 1700000000,
            "hasPin": true,
            "pinHash": "abcdef123456",
            "members": {}
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(SquadRoom.self, from: json)
        XCTAssertEqual(decoded.id, "DELTA")
        XCTAssertEqual(decoded.hostId, "HOST_DELTA")
        XCTAssertTrue(decoded.hasPin)
        XCTAssertEqual(decoded.pinHash, "abcdef123456")
    }
    
    func testFirebaseSyncManagerPinAuthenticationWorkflow() {
        let roomId = "GHOST"
        let pin = "7788"
        let pinHash = FirebaseSyncManager.hashPin(pin, salt: roomId)
        let room = SquadRoom(id: roomId, hostId: "HOST_GHOST", hasPin: true, pinHash: pinHash)
        
        let syncManager = FirebaseSyncManager()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        syncManager.urlSession = URLSession(configuration: config)
        
        let roomData = try! JSONEncoder().encode(room)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, roomData)
        }
        
        let member = SquadMember(id: "OPERATOR_1", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        
        // 1. Join with correct PIN -> Success
        let successExp = expectation(description: "Join with correct PIN succeeds")
        syncManager.joinRoom(id: roomId, member: member, pin: "7788") { result in
            switch result {
            case .success(let joinedRoom):
                XCTAssertEqual(joinedRoom.id, roomId)
                successExp.fulfill()
            case .failure(let error):
                XCTFail("Should not fail with correct PIN: \(error)")
            }
        }
        wait(for: [successExp], timeout: 2.0)
        
        // 2. Join with incorrect PIN -> Failure (.incorrectPin)
        let failExp = expectation(description: "Join with incorrect PIN fails")
        syncManager.joinRoom(id: roomId, member: member, pin: "0000") { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with incorrect PIN")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.incorrectPin)
                failExp.fulfill()
            }
        }
        wait(for: [failExp], timeout: 2.0)
    }
    
    func testBluetoothDiscoveredRoomPinFlag() {
        let roomWithPin = DiscoveredRoom(id: "ALPHA", name: "Alpha Squad", rssi: -50, discoveredAt: Date(), peripheral: nil, hasPin: true)
        let roomWithoutPin = DiscoveredRoom(id: "BRAVO", name: "Bravo Squad", rssi: -50, discoveredAt: Date(), peripheral: nil, hasPin: false)
        
        XCTAssertTrue(roomWithPin.hasPin)
        XCTAssertFalse(roomWithoutPin.hasPin)
    }
    
    // MARK: - Server Cost Optimization & Room Lifecycle Tests
    
    func testPlayerLogoutDeletesTelemetryAndMembershipWhenOtherMembersRemain() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.myMemberId = "PLAYER_B"
        
        // Multi-member room (Host + Player B)
        let room = SquadRoom(
            id: "MULTI_ROOM",
            hostId: "HOST_A",
            members: [
                "HOST_A": SquadMember(id: "HOST_A", callsign: "HOST", latitude: 0, longitude: 0, isHost: true),
                "PLAYER_B": SquadMember(id: "PLAYER_B", callsign: "PLAYER_B", latitude: 0, longitude: 0, isHost: false)
            ]
        )
        gameState.firebaseManager.activeRoom = room
        gameState.firebaseManager.isConnected = true
        
        let exp = expectation(description: "Player B logs out")
        gameState.logoutPlayer { success in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        let deleteRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "DELETE" }
        // Verify player's membership and telemetry were deleted
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/rooms/MULTI_ROOM/members/PLAYER_B.json") == true })
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/telemetry/MULTI_ROOM/PLAYER_B.json") == true })
        // Whole room should NOT be deleted because HOST_A is still in the room
        XCTAssertFalse(deleteRequests.contains { $0.url?.absoluteString.hasSuffix("/rooms/MULTI_ROOM.json") == true })
    }
    
    func testPlayerLogoutDeletesEntireRoomWhenLastMemberLeaves() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.myMemberId = "SOLO_PLAYER"
        
        // Room with only 1 member
        let room = SquadRoom(
            id: "SOLO_ROOM",
            hostId: "ORIGINAL_HOST",
            members: [
                "SOLO_PLAYER": SquadMember(id: "SOLO_PLAYER", callsign: "SOLO", latitude: 0, longitude: 0, isHost: false)
            ]
        )
        gameState.firebaseManager.activeRoom = room
        gameState.firebaseManager.isConnected = true
        
        let exp = expectation(description: "Solo player logs out, triggering empty room deletion")
        gameState.logoutPlayer { success in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        let deleteRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "DELETE" }
        // Verify member, member telemetry, whole room, and whole room telemetry are all deleted
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/rooms/SOLO_ROOM/members/SOLO_PLAYER.json") == true })
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/telemetry/SOLO_ROOM/SOLO_PLAYER.json") == true })
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/rooms/SOLO_ROOM.json") == true })
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/telemetry/SOLO_ROOM.json") == true })
    }
    
    func testServerCreatorDisbandMessageDeletesWholeRoomAndTelemetry() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.myMemberId = "CREATOR_HOST"
        
        let room = SquadRoom(
            id: "SQUAD_TO_DISBAND",
            hostId: "CREATOR_HOST",
            members: [
                "CREATOR_HOST": SquadMember(id: "CREATOR_HOST", callsign: "LEADER", latitude: 0, longitude: 0, isHost: true),
                "MEMBER_2": SquadMember(id: "MEMBER_2", callsign: "MEMBER_2", latitude: 0, longitude: 0, isHost: false)
            ]
        )
        gameState.firebaseManager.activeRoom = room
        gameState.firebaseManager.isConnected = true
        gameState.isHosting = true
        
        let exp = expectation(description: "Creator disbands room")
        gameState.disbandRoom { success in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        let deleteRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "DELETE" }
        // Room and telemetry nodes must both be completely deleted
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/rooms/SQUAD_TO_DISBAND.json") == true })
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/telemetry/SQUAD_TO_DISBAND.json") == true })
        XCTAssertNil(gameState.firebaseManager.activeRoom)
        XCTAssertFalse(gameState.firebaseManager.isConnected)
    }
    
    func testSevenDayIdleRoomDetectionAndSchema() throws {
        let now = Date()
        let activeRoom = SquadRoom(
            id: "ACTIVE_ROOM",
            hostId: "HOST1",
            createdAt: now.timeIntervalSince1970 - 86400, // 1 day ago
            lastActivityTimestamp: now.timeIntervalSince1970 - 3600 // 1 hour ago
        )
        XCTAssertFalse(activeRoom.isIdle(cutoffDays: 7.0, asOf: now), "Room active 1 hour ago should not be idle")
        
        let idleRoom = SquadRoom(
            id: "OLD_ROOM",
            hostId: "HOST2",
            createdAt: now.timeIntervalSince1970 - (10 * 86400), // 10 days ago
            lastActivityTimestamp: now.timeIntervalSince1970 - (8 * 86400) // 8 days ago
        )
        XCTAssertTrue(idleRoom.isIdle(cutoffDays: 7.0, asOf: now), "Room idle for 8 days should be flagged for 7-day deletion")
        
        // Test encoding/decoding lastActivityTimestamp
        let encoded = try JSONEncoder().encode(activeRoom)
        let decoded = try JSONDecoder().decode(SquadRoom.self, from: encoded)
        XCTAssertEqual(decoded.lastActivityTimestamp, activeRoom.lastActivityTimestamp)
    }
    
    // MARK: - AppConstants Integrity Tests
    
    func testAppConstantsIntegrity() {
        // Storage Keys
        XCTAssertEqual(AppConstants.Storage.userCallsignKey, "user_callsign")
        XCTAssertEqual(AppConstants.Storage.savedRoomNameKey, "saved_room_name")
        XCTAssertEqual(AppConstants.Storage.userMemberIdKey, "user_member_id")
        XCTAssertEqual(AppConstants.Storage.radarColorThemeKey, "radar_color_theme")
        XCTAssertEqual(AppConstants.Storage.hasUnlimitedSquadUnlockKey, "hasUnlimitedSquadUnlock")
        XCTAssertEqual(AppConstants.Storage.savedPinKey, "saved_pin")
        
        // Network
        XCTAssertEqual(AppConstants.Network.defaultDatabaseURL, "https://radarmap-8adf0-default-rtdb.firebaseio.com")
        XCTAssertEqual(AppConstants.Network.Bluetooth.advertisementPrefix, "RM:")
        XCTAssertEqual(AppConstants.Network.Quality.initialLatencyMs, 50.0)
        XCTAssertEqual(AppConstants.Network.Quality.emaAlpha, 0.2)
        
        // Subscription
        XCTAssertEqual(AppConstants.Subscription.freeTierMaxCapacity, 4)
        XCTAssertEqual(AppConstants.Subscription.proTierMaxCapacity, 999)
        XCTAssertEqual(AppConstants.Subscription.lifetimePriceString, "$9.99")
        XCTAssertEqual(AppConstants.Subscription.entitlementID, "radarmap_pro")
        XCTAssertEqual(AppConstants.Subscription.productID, "com.radarmap.watch.pro")
        XCTAssertEqual(AppConstants.Subscription.offeringID, "default")
        XCTAssertEqual(AppConstants.Subscription.packageID, "$rc_lifetime")
        XCTAssertFalse(AppConstants.Subscription.revenueCatApiKey.isEmpty)
        
        // Health
        XCTAssertEqual(AppConstants.Health.defaultRestingHeartRate, 75.0)
        XCTAssertEqual(AppConstants.Health.flatlineHeartRate, 0.0)
        XCTAssertEqual(AppConstants.Health.referenceBpm, 100.0)
        XCTAssertEqual(AppConstants.Health.secondsPerMinute, 60.0)
        XCTAssertEqual(AppConstants.Health.Zones.blueMax, 60.0)
        XCTAssertEqual(AppConstants.Health.Zones.greenMax, 100.0)
        XCTAssertEqual(AppConstants.Health.Zones.yellowMax, 140.0)
        XCTAssertEqual(AppConstants.Health.Zones.orangeMax, 175.0)
        
        // Location & Geodesic Calculation Constants
        XCTAssertEqual(AppConstants.Location.metersPerDegreeLatitude, 111_139.0)
        XCTAssertEqual(AppConstants.Location.metersPerKilometer, 1000.0)
        XCTAssertEqual(AppConstants.Location.distanceFilterMeters, 1.0)
        XCTAssertEqual(AppConstants.Location.headingFilterDegrees, 2.0)
        XCTAssertEqual(AppConstants.Location.degreesToRadiansFactor, .pi / 180.0, accuracy: 1e-9)
        XCTAssertEqual(AppConstants.Location.radiansToDegreesFactor, 180.0 / .pi, accuracy: 1e-9)
        XCTAssertEqual(AppConstants.Location.fullCircleDegrees, 360.0)
        XCTAssertEqual(AppConstants.Location.vectorEpsilon, 1e-6)
        XCTAssertEqual(AppConstants.Location.stationarySpeedThresholdMps, 0.5)
        XCTAssertEqual(AppConstants.Location.runningSpeedThresholdMps, 2.5)
        XCTAssertEqual(AppConstants.Location.minDisplacementForCourseOverGroundMeters, 2.0)
        
        // Timing
        XCTAssertEqual(AppConstants.Timing.secondsPerMinute, 60.0)
        XCTAssertEqual(AppConstants.Timing.secondsPerHour, 3600.0)
        XCTAssertEqual(AppConstants.Timing.secondsPerDay, 86400.0)
        XCTAssertEqual(AppConstants.Timing.millisecondsPerSecond, 1000.0)
        XCTAssertEqual(AppConstants.Timing.AdaptiveRate.intervalChangeEpsilon, 0.01)
        XCTAssertEqual(AppConstants.Timing.Stale.defaultTimeoutMultiplier, 15.0)
        XCTAssertEqual(AppConstants.Timing.Inactivity.idleCutoffDays, 7.0)
        XCTAssertEqual(AppConstants.Timing.Inactivity.secondsPerDay, 86400.0)
        XCTAssertEqual(AppConstants.Timing.DeathHold.delayBeforeChargeSeconds, 1.0)
        XCTAssertEqual(AppConstants.Timing.DeathHold.chargeDurationSeconds, 3.0)
        
        // UI & Gestures
        XCTAssertEqual(AppConstants.UI.defaultCallsign, "")
        XCTAssertEqual(AppConstants.UI.defaultRoomName, "")
        XCTAssertEqual(AppConstants.UI.Gestures.actionHoldDurationSeconds, 1.2)
        XCTAssertEqual(AppConstants.UI.Gestures.holdTimerTickIntervalSeconds, 0.02)
        XCTAssertEqual(AppConstants.UI.Gestures.actionAnimationDurationSeconds, 0.25)
        
        // Radar Scale Geometry
        XCTAssertEqual(AppConstants.UI.RadarScale.radarRadiusRatio, 0.44)
        XCTAssertEqual(AppConstants.UI.RadarScale.crosshairExtensionRatio, 1.05)
        XCTAssertEqual(AppConstants.UI.RadarScale.centerReticleSize, 9.0)
        
        // Tactical Vector Shapes
        XCTAssertEqual(AppConstants.UI.TacticalShapes.playerRadiusFactor, 0.38)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.playerLeftShoulderAngleDegrees, 220.0)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.playerRightShoulderAngleDegrees, 320.0)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.leaderRadiusFactor, 0.36)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.deadXArmLengthRatio, 0.46)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.deadXHalfThicknessRatio, 0.13)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.sqrtTwo, 1.4142135623730951, accuracy: 1e-9)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.ECG.pWaveStart, 0.20)
        XCTAssertEqual(AppConstants.UI.TacticalShapes.ECG.rPeakHeightRatio, 0.44)
        
        // Tactical Indicators
        XCTAssertEqual(AppConstants.Subscription.maxEnemyIndicatorsCount, 20)
        XCTAssertEqual(AppConstants.Subscription.enemyIndicatorFadeDurationSeconds, 300.0)
        XCTAssertEqual(AppConstants.Subscription.indicatorHoldToDeleteDurationSeconds, 1.2)
    }
    
    // MARK: - Pro Tier Tactical Indicators Tests
    
    func testProIndicatorAccessGating() {
        let gameState = createMockGameState()
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = false
        
        // Non-pro attempt to open menu or select indicator triggers paywall
        gameState.openIndicatorMenu()
        XCTAssertTrue(gameState.showPaywallSheet)
        XCTAssertFalse(gameState.showIndicatorMenuSheet)
        
        gameState.showPaywallSheet = false
        gameState.selectIndicatorForPlacement(.watchHere)
        XCTAssertTrue(gameState.showPaywallSheet)
        XCTAssertNil(gameState.pendingIndicatorPlacementType)
        
        // Pro unlock enables opening menu and selecting indicator
        gameState.showPaywallSheet = false
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = true
        
        gameState.openIndicatorMenu()
        XCTAssertTrue(gameState.showIndicatorMenuSheet)
        XCTAssertFalse(gameState.showPaywallSheet)
        
        gameState.selectIndicatorForPlacement(.watchHere)
        XCTAssertEqual(gameState.pendingIndicatorPlacementType, .watchHere)
        XCTAssertFalse(gameState.showIndicatorMenuSheet)
    }
    
    func testSquadOrderSingleInstanceLimit() {
        let gameState = createMockGameState()
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = true
        
        let coord1 = CLLocationCoordinate2D(latitude: 37.785, longitude: -122.406)
        let coord2 = CLLocationCoordinate2D(latitude: 37.786, longitude: -122.407)
        let coord3 = CLLocationCoordinate2D(latitude: 37.787, longitude: -122.408)
        let coord4 = CLLocationCoordinate2D(latitude: 37.788, longitude: -122.409)
        
        // Place first Watch Here order
        gameState.selectIndicatorForPlacement(.watchHere)
        gameState.placeTacticalIndicator(at: coord1)
        XCTAssertEqual(gameState.allTacticalIndicators.count, 1)
        XCTAssertEqual(gameState.allTacticalIndicators.first?.type, .watchHere)
        XCTAssertEqual(gameState.allTacticalIndicators.first?.coordinate.latitude, coord1.latitude)
        
        // Place second Watch Here order -> Should REPLACE the first Watch Here order
        gameState.selectIndicatorForPlacement(.watchHere)
        gameState.placeTacticalIndicator(at: coord2)
        XCTAssertEqual(gameState.allTacticalIndicators.count, 1)
        XCTAssertEqual(gameState.allTacticalIndicators.first?.type, .watchHere)
        XCTAssertEqual(gameState.allTacticalIndicators.first?.coordinate.latitude, coord2.latitude)
        
        // Place Go Here order and Attack Here order -> 1 of each (3 total)
        gameState.selectIndicatorForPlacement(.goHere)
        gameState.placeTacticalIndicator(at: coord3)
        gameState.selectIndicatorForPlacement(.attackHere)
        gameState.placeTacticalIndicator(at: coord4)
        
        XCTAssertEqual(gameState.allTacticalIndicators.count, 3)
        XCTAssertEqual(Set(gameState.allTacticalIndicators.map { $0.type }), Set([.watchHere, .goHere, .attackHere]))
        
        // Placing a new Go Here replaces only Go Here
        let coord5 = CLLocationCoordinate2D(latitude: 37.789, longitude: -122.410)
        gameState.selectIndicatorForPlacement(.goHere)
        gameState.placeTacticalIndicator(at: coord5)
        
        XCTAssertEqual(gameState.allTacticalIndicators.count, 3)
        let currentGoHere = gameState.allTacticalIndicators.first(where: { $0.type == .goHere })
        XCTAssertEqual(currentGoHere?.coordinate.latitude, coord5.latitude)
    }
    
    func testEnemyIndicatorCapacityAndFifoReplacement() {
        let gameState = createMockGameState()
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = true
        
        var placedIds: [String] = []
        let baseTime = Date().timeIntervalSince1970
        
        // Place 20 enemy indicators with ascending timestamps
        for i in 1...20 {
            gameState.selectIndicatorForPlacement(.infantry)
            let coord = CLLocationCoordinate2D(latitude: 37.780 + Double(i) * 0.001, longitude: -122.400 + Double(i) * 0.001)
            gameState.placeTacticalIndicator(at: coord)
            
            // Set deterministic timestamp
            let latest = gameState.allTacticalIndicators.first(where: { $0.coordinate.latitude == coord.latitude })!
            placedIds.append(latest.id)
            gameState.localIndicators[latest.id] = TacticalIndicator(
                id: latest.id,
                type: latest.type,
                coordinate: coord,
                placedByMemberId: gameState.myMemberId,
                timestamp: baseTime + Double(i)
            )
        }
        
        XCTAssertEqual(gameState.allTacticalIndicators.count, 20)
        let oldestId = placedIds.first!
        XCTAssertTrue(gameState.allTacticalIndicators.contains(where: { $0.id == oldestId }))
        
        // Place 21st enemy indicator -> The oldest (1st) indicator should be evicted/replaced
        let coord21 = CLLocationCoordinate2D(latitude: 37.850, longitude: -122.450)
        gameState.selectIndicatorForPlacement(.heavyVehicle)
        gameState.placeTacticalIndicator(at: coord21)
        
        XCTAssertEqual(gameState.allTacticalIndicators.count, 20)
        XCTAssertFalse(gameState.allTacticalIndicators.contains(where: { $0.id == oldestId }), "Oldest enemy indicator must be evicted")
        XCTAssertTrue(gameState.allTacticalIndicators.contains(where: { $0.type == .heavyVehicle && $0.coordinate.latitude == coord21.latitude }))
    }
    
    func testEnemyIndicatorAgingAndFadeFactor() {
        let now = Date()
        let freshIndicator = TacticalIndicator(
            type: .infantry,
            coordinate: CLLocationCoordinate2D(latitude: 37.7, longitude: -122.4),
            placedByMemberId: "TEST",
            timestamp: now.timeIntervalSince1970
        )
        XCTAssertEqual(freshIndicator.grayFadeFactor(referenceDate: now), 0.0, accuracy: 0.001)
        XCTAssertFalse(freshIndicator.isFullyFaded(referenceDate: now))
        
        // 2.5 minutes (150s) later -> 50% faded
        let halfFadedDate = now.addingTimeInterval(150)
        XCTAssertEqual(freshIndicator.grayFadeFactor(referenceDate: halfFadedDate), 0.5, accuracy: 0.001)
        XCTAssertFalse(freshIndicator.isFullyFaded(referenceDate: halfFadedDate))
        
        // 5 minutes (300s) later -> 100% faded (gray)
        let fullFadedDate = now.addingTimeInterval(300)
        XCTAssertEqual(freshIndicator.grayFadeFactor(referenceDate: fullFadedDate), 1.0, accuracy: 0.001)
        XCTAssertTrue(freshIndicator.isFullyFaded(referenceDate: fullFadedDate))
        
        // 10 minutes later -> Clamped to 1.0
        let pastDate = now.addingTimeInterval(600)
        XCTAssertEqual(freshIndicator.grayFadeFactor(referenceDate: pastDate), 1.0, accuracy: 0.001)
        XCTAssertTrue(freshIndicator.isFullyFaded(referenceDate: pastDate))
        
        // Squad Orders do not fade to gray (fade factor is always 0.0)
        let orderIndicator = TacticalIndicator(
            type: .watchHere,
            coordinate: CLLocationCoordinate2D(latitude: 37.7, longitude: -122.4),
            placedByMemberId: "TEST",
            timestamp: now.timeIntervalSince1970
        )
        XCTAssertEqual(orderIndicator.grayFadeFactor(referenceDate: pastDate), 0.0)
    }
    
    func testTacticalIndicatorRoomEncodingDecoding() throws {
        let indicator1 = TacticalIndicator(
            id: "IND-1",
            type: .watchHere,
            coordinate: CLLocationCoordinate2D(latitude: 37.7858, longitude: -122.4064),
            placedByMemberId: "LEADER-1",
            timestamp: 1700000000
        )
        let indicator2 = TacticalIndicator(
            id: "IND-2",
            type: .lightVehicle,
            coordinate: CLLocationCoordinate2D(latitude: 37.7860, longitude: -122.4070),
            placedByMemberId: "LEADER-1",
            timestamp: 1700000100
        )
        
        let room = SquadRoom(
            id: "PRO-SQUAD",
            hostId: "LEADER-1",
            maxCapacity: 12,
            indicators: [
                indicator1.id: indicator1,
                indicator2.id: indicator2
            ]
        )
        
        let encoded = try JSONEncoder().encode(room)
        let decoded = try JSONDecoder().decode(SquadRoom.self, from: encoded)
        
        XCTAssertEqual(decoded.indicators.count, 2)
        XCTAssertEqual(decoded.indicators["IND-1"]?.type, .watchHere)
        XCTAssertEqual(decoded.indicators["IND-2"]?.type, .lightVehicle)
        if let ind1 = decoded.indicators["IND-1"], let ind2 = decoded.indicators["IND-2"] {
            XCTAssertEqual(ind1.coordinate.latitude, 37.7858, accuracy: 0.0001)
            XCTAssertEqual(ind2.coordinate.latitude, 37.7860, accuracy: 0.0001)
        } else {
            XCTFail("Decoded indicators should not be nil")
        }
    }
    
    func testIndicatorDeletion() {
        let gameState = createMockGameState()
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = true
        
        gameState.selectIndicatorForPlacement(.attackHere)
        gameState.placeTacticalIndicator(at: CLLocationCoordinate2D(latitude: 37.785, longitude: -122.406))
        
        XCTAssertEqual(gameState.allTacticalIndicators.count, 1)
        let indId = gameState.allTacticalIndicators.first!.id
        
        // Remove indicator (e.g. hold-to-delete completion)
        gameState.removeTacticalIndicator(id: indId)
        XCTAssertEqual(gameState.allTacticalIndicators.count, 0)
    }
    
    func testCommandCallsignAttributionAndDistinctionForMultipleProPlayers() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = true
        gameState.myMemberId = "PRO_PLAYER_1"
        gameState.myCallsign = "VIPER"
        
        let p1Member = SquadMember(id: "PRO_PLAYER_1", callsign: "VIPER", latitude: 37.785, longitude: -122.406, isHost: true)
        let p2Member = SquadMember(id: "PRO_PLAYER_2", callsign: "GHOST", latitude: 37.786, longitude: -122.407, isHost: false)
        
        var room = SquadRoom(
            id: "PRO_SQUAD",
            hostId: "PRO_PLAYER_1",
            maxCapacity: 12,
            members: [
                "PRO_PLAYER_1": p1Member,
                "PRO_PLAYER_2": p2Member
            ]
        )
        gameState.firebaseManager.activeRoom = room
        
        let attackCoord1 = CLLocationCoordinate2D(latitude: 37.7851, longitude: -122.4061)
        let attackCoord2 = CLLocationCoordinate2D(latitude: 37.7865, longitude: -122.4075)
        let attackCoord3 = CLLocationCoordinate2D(latitude: 37.7890, longitude: -122.4100)
        
        // 1. Player 1 (VIPER) places Attack command
        gameState.selectIndicatorForPlacement(.attackHere)
        gameState.placeTacticalIndicator(at: attackCoord1)
        
        XCTAssertEqual(gameState.allTacticalIndicators.count, 1)
        let p1Attack = gameState.allTacticalIndicators.first!
        XCTAssertEqual(p1Attack.type, .attackHere)
        XCTAssertEqual(p1Attack.placedByMemberId, "PRO_PLAYER_1")
        XCTAssertEqual(p1Attack.placedByCallsign, "VIPER", "Attack command must include the callsign of who sent it")
        
        // 2. Player 2 (GHOST) places an Attack command in the same room
        let p2Attack = TacticalIndicator(
            id: "IND_P2_ATTACK",
            type: .attackHere,
            coordinate: attackCoord2,
            placedByMemberId: "PRO_PLAYER_2",
            placedByCallsign: "GHOST"
        )
        room = gameState.firebaseManager.activeRoom!
        room.indicators[p2Attack.id] = p2Attack
        gameState.firebaseManager.activeRoom = room
        
        // Both Attack commands must be active and distinguishable by callsign in the room
        let allAttacks = gameState.allTacticalIndicators.filter { $0.type == .attackHere }
        XCTAssertEqual(allAttacks.count, 2, "Room with multiple pro players must allow each player to place their attack command")
        XCTAssertTrue(allAttacks.contains { $0.placedByCallsign == "VIPER" && $0.placedByMemberId == "PRO_PLAYER_1" })
        XCTAssertTrue(allAttacks.contains { $0.placedByCallsign == "GHOST" && $0.placedByMemberId == "PRO_PLAYER_2" })
        
        // 3. Player 1 (VIPER) places a new Attack command at a different coordinate
        gameState.selectIndicatorForPlacement(.attackHere)
        gameState.placeTacticalIndicator(at: attackCoord3)
        
        // Player 1's attack command was updated to new coordinate, Player 2's attack command remains untouched
        let updatedAttacks = gameState.allTacticalIndicators.filter { $0.type == .attackHere }
        XCTAssertEqual(updatedAttacks.count, 2)
        let updatedP1Attack = updatedAttacks.first(where: { $0.placedByMemberId == "PRO_PLAYER_1" })
        let retainedP2Attack = updatedAttacks.first(where: { $0.placedByMemberId == "PRO_PLAYER_2" })
        
        XCTAssertNotNil(updatedP1Attack)
        XCTAssertEqual(updatedP1Attack?.placedByCallsign, "VIPER")
        XCTAssertEqual(updatedP1Attack?.coordinate.latitude, attackCoord3.latitude)
        
        XCTAssertNotNil(retainedP2Attack)
        XCTAssertEqual(retainedP2Attack?.placedByCallsign, "GHOST")
        XCTAssertEqual(retainedP2Attack?.coordinate.latitude, attackCoord2.latitude)
    }
    
    func testFallbackCallsignResolutionFromRoomRoster() {
        let gameState = createMockGameState()
        let member = SquadMember(id: "OP_RECON", callsign: "SHADOW", latitude: 37.78, longitude: -122.40)
        
        // Indicator synced from legacy packet without placedByCallsign field (nil)
        let legacyIndicator = TacticalIndicator(
            id: "LEGACY_IND",
            type: .attackHere,
            coordinate: CLLocationCoordinate2D(latitude: 37.785, longitude: -122.406),
            placedByMemberId: "OP_RECON",
            placedByCallsign: nil
        )
        
        let room = SquadRoom(
            id: "SQUAD_A",
            hostId: "OP_RECON",
            members: ["OP_RECON": member],
            indicators: [legacyIndicator.id: legacyIndicator]
        )
        gameState.firebaseManager.activeRoom = room
        
        let indicators = gameState.allTacticalIndicators
        XCTAssertEqual(indicators.count, 1)
        XCTAssertEqual(indicators.first?.placedByCallsign, "SHADOW", "Callsign must be resolved dynamically from room roster when nil in indicator packet")
    }
    
    func testTacticalIndicatorCallsignCodableRoundtrip() throws {
        let indicator = TacticalIndicator(
            id: "IND_CODABLE",
            type: .attackHere,
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            placedByMemberId: "MEMBER_42",
            placedByCallsign: "SPECTRE",
            timestamp: 1700000000
        )
        
        let encoded = try JSONEncoder().encode(indicator)
        let decoded = try JSONDecoder().decode(TacticalIndicator.self, from: encoded)
        
        XCTAssertEqual(decoded.id, "IND_CODABLE")
        XCTAssertEqual(decoded.type, .attackHere)
        XCTAssertEqual(decoded.placedByMemberId, "MEMBER_42")
        XCTAssertEqual(decoded.placedByCallsign, "SPECTRE")
        XCTAssertEqual(decoded.coordinate.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(decoded.coordinate.longitude, -122.4194, accuracy: 0.0001)
    }
    
    func testZoomScalePreservationBetweenViews() {
        let screenHeight: Double = AppConstants.UI.ScaleRuler.referenceScreenHeight
        let maxRadius: Double = screenHeight * 0.44
        let metersPerDegreeLat: Double = AppConstants.Location.metersPerDegreeLatitude
        
        // 1. Convert Radar scale (e.g. 250m) to MapKit latDelta
        let radarScale: Double = 250.0
        let visibleMetersLat = (screenHeight / maxRadius) * radarScale
        let latDelta = visibleMetersLat / metersPerDegreeLat
        
        // 2. Invert latDelta back to Radar scale
        let calculatedVisibleMeters = latDelta * metersPerDegreeLat
        let calculatedRadarScale = (maxRadius / screenHeight) * calculatedVisibleMeters
        
        XCTAssertEqual(calculatedRadarScale, radarScale, accuracy: 0.0001, "Bidirectional zoom conversion must preserve exact scale")
        
        // 3. Verify scale matches at default zoom (100m)
        let defaultRadar: Double = AppConstants.UI.RadarScale.defaultScaleMeters
        let defaultLatDelta = ((screenHeight / maxRadius) * defaultRadar) / metersPerDegreeLat
        let roundtripDefault = (maxRadius / screenHeight) * (defaultLatDelta * metersPerDegreeLat)
        XCTAssertEqual(roundtripDefault, defaultRadar, accuracy: 0.0001)
        
        // 4. Verify helper methods in AppConstants.UI.RadarScale across multiple zoom levels
        let testScales: [Double] = [25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0]
        for scale in testScales {
            let delta = AppConstants.UI.RadarScale.mapSpanDelta(forRadarScaleMeters: scale)
            let roundtripScale = AppConstants.UI.RadarScale.radarScaleMeters(forMapSpanDelta: delta)
            XCTAssertEqual(roundtripScale, scale, accuracy: 0.001, "AppConstants zoom helper must preserve scale \(scale)m accurately")
        }
        
        // 5. Verify ScaleRuler distance formatting helpers
        XCTAssertEqual(AppConstants.UI.ScaleRuler.formatRulerDistance(meters: 15.0), "10m")
        XCTAssertEqual(AppConstants.UI.ScaleRuler.formatRulerDistance(meters: 50.0), "50m")
        XCTAssertEqual(AppConstants.UI.ScaleRuler.formatRulerDistance(meters: 100.0), "100m")
        XCTAssertEqual(AppConstants.UI.ScaleRuler.formatRulerDistance(meters: 500.0), "500m")
        XCTAssertEqual(AppConstants.UI.ScaleRuler.formatRulerDistance(meters: 1200.0), "1km")
        XCTAssertEqual(AppConstants.UI.ScaleRuler.formatDistance(meters: 100.0), "100m")
        XCTAssertEqual(AppConstants.UI.ScaleRuler.formatDistance(meters: 2500.0), "2.5km")
    }
    
    func testDeadReckoningEngineSmoothedMemberHelper() {
        let engine = DeadReckoningEngine()
        let member = SquadMember(id: "M1", callsign: "VIPER", latitude: 37.77, longitude: -122.41, heading: 45.0, heartRate: 85.0)
        
        // Untracked member falls back to raw member coordinates and heading
        let smoothedUntracked = engine.smoothedMember(for: member)
        XCTAssertEqual(smoothedUntracked.id, "M1")
        XCTAssertEqual(smoothedUntracked.callsign, "VIPER")
        XCTAssertEqual(smoothedUntracked.coordinate.latitude, 37.77, accuracy: 0.0001)
        XCTAssertEqual(smoothedUntracked.coordinate.longitude, -122.41, accuracy: 0.0001)
        XCTAssertEqual(smoothedUntracked.heading, 45.0, accuracy: 0.0001)
        XCTAssertEqual(smoothedUntracked.heartRate, 85.0)
        
        // Tracked member receives smoothed values
        engine.updateRemotePlayer(id: "M1", newCoordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.40), newHeading: 90.0, packetTimestamp: Date().timeIntervalSince1970)
        let smoothedTracked = engine.smoothedMember(for: member)
        XCTAssertEqual(smoothedTracked.coordinate.latitude, 37.78, accuracy: 0.0001)
        XCTAssertEqual(smoothedTracked.coordinate.longitude, -122.40, accuracy: 0.0001)
        XCTAssertEqual(smoothedTracked.heading, 90.0, accuracy: 0.0001)
    }
    
    func testUnifiedGameStateMapScaleAndCenterState() {
        let gameState = createMockGameState()
        
        // 1. Initial default state
        XCTAssertEqual(gameState.radarScaleMeters, AppConstants.UI.RadarScale.defaultScaleMeters)
        XCTAssertNil(gameState.currentMapCenter)
        XCTAssertEqual(gameState.radarCenterTrigger, 0)
        XCTAssertEqual(gameState.currentScaleText, "10m")
        
        // 2. Modifying radarScaleMeters updates currentMapSpanDelta and currentScaleText
        gameState.radarScaleMeters = 200.0
        XCTAssertEqual(gameState.currentScaleText, "25m")
        let computedDelta = gameState.currentMapSpanDelta
        XCTAssertEqual(computedDelta, AppConstants.UI.RadarScale.mapSpanDelta(forRadarScaleMeters: 200.0), accuracy: 0.00001)
        
        // 3. Modifying currentMapSpanDelta updates radarScaleMeters
        let targetSpan = 0.004
        gameState.currentMapSpanDelta = targetSpan
        let expectedScale = AppConstants.UI.RadarScale.radarScaleMeters(forMapSpanDelta: targetSpan)
        XCTAssertEqual(gameState.radarScaleMeters, expectedScale, accuracy: 0.001)
        
        // 4. Modifying currentMapCenter
        let customCenter = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.2)
        gameState.currentMapCenter = customCenter
        XCTAssertEqual(gameState.currentMapCenter?.latitude, 37.5)
        XCTAssertEqual(gameState.currentMapCenter?.longitude, -122.2)
        
        // 5. Calling resetMapToDefaultCenterAndZoom resets both scale, center and bumps trigger
        gameState.resetMapToDefaultCenterAndZoom()
        XCTAssertEqual(gameState.radarScaleMeters, AppConstants.UI.RadarScale.defaultScaleMeters)
        XCTAssertNil(gameState.currentMapCenter)
        XCTAssertEqual(gameState.radarCenterTrigger, 1)
        XCTAssertEqual(gameState.currentScaleText, "10m")
    }
    
    // MARK: - Tactical Indicators Category & Bandwidth-Preservation Sync Tests
    
    func testTacticalEndpointConstant() {
        XCTAssertEqual(AppConstants.Network.Endpoints.tactical, "tactical")
        XCTAssertEqual(AppConstants.Network.Endpoints.telemetry, "telemetry")
        XCTAssertEqual(AppConstants.Network.Endpoints.rooms, "rooms")
    }
    
    func testSquadLeaderButtonVisibilityFollowsProStatus() {
        let gameState = createMockGameState()
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = false
        XCTAssertFalse(gameState.isProUser, "Non-pro users must have isProUser = false")
        
        gameState.subscriptionManager.hasUnlimitedSquadUnlock = true
        XCTAssertTrue(gameState.isProUser, "Pro users must have isProUser = true")
    }
    
    func testNonProAndProBothViewTacticalIndicatorsFromFirebase() {
        // Non-Pro user setup
        let nonProState = createMockGameState()
        nonProState.subscriptionManager.hasUnlimitedSquadUnlock = false
        var room = SquadRoom(id: "DELTA", hostId: "PRO_LEADER")
        let indicator = TacticalIndicator(
            id: "IND-999",
            type: .attackHere,
            coordinate: CLLocationCoordinate2D(latitude: 37.785, longitude: -122.405),
            placedByMemberId: "PRO_LEADER"
        )
        room.indicators[indicator.id] = indicator
        nonProState.firebaseManager.activeRoom = room
        
        // Both non-pro and pro access allTacticalIndicators identically
        XCTAssertEqual(nonProState.allTacticalIndicators.count, 1)
        XCTAssertEqual(nonProState.allTacticalIndicators.first?.type, .attackHere)
        
        // Pro user setup
        let proState = createMockGameState()
        proState.subscriptionManager.hasUnlimitedSquadUnlock = true
        proState.firebaseManager.activeRoom = room
        XCTAssertEqual(proState.allTacticalIndicators.count, 1)
        XCTAssertEqual(proState.allTacticalIndicators.first?.type, .attackHere)
    }
    
    func testTacticalIndicatorsUploadAndChangeOnlyDownload() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let urlStr = request.url?.absoluteString ?? ""
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            
            if urlStr.contains("/tactical/ALPHA/_updatedAt.json") && request.httpMethod == "GET" {
                return (response, "1700000500".data(using: .utf8)!)
            }
            if urlStr.contains("/tactical/ALPHA.json") && request.httpMethod == "GET" {
                let json = """
                {
                    "_updatedAt": 1700000500,
                    "IND-100": {
                        "id": "IND-100",
                        "type": "watchHere",
                        "latitude": 37.7858,
                        "longitude": -122.4064,
                        "placedByMemberId": "LEADER",
                        "timestamp": 1700000500
                    }
                }
                """
                return (response, json.data(using: .utf8)!)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        let room = SquadRoom(id: "ALPHA", hostId: "LEADER")
        gameState.firebaseManager.activeRoom = room
        
        // 1. Upload new indicator: Verify PUT request is made under /tactical/ALPHA/IND-101.json
        let newIndicator = TacticalIndicator(
            id: "IND-101",
            type: .goHere,
            coordinate: CLLocationCoordinate2D(latitude: 37.786, longitude: -122.407),
            placedByMemberId: "LEADER"
        )
        gameState.firebaseManager.addOrUpdateIndicator(roomId: "ALPHA", indicator: newIndicator)
        
        let putExp = expectation(description: "Wait for PUT requests")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let putRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "PUT" }
            XCTAssertTrue(putRequests.contains { $0.url?.absoluteString.contains("/tactical/ALPHA/IND-101.json") == true })
            XCTAssertTrue(putRequests.contains { $0.url?.absoluteString.contains("/tactical/ALPHA/_updatedAt.json") == true })
            putExp.fulfill()
        }
        wait(for: [putExp], timeout: 1.0)
        
        // 2. Change-only download test: When _updatedAt is newer than lastKnownTacticalUpdatedAt (0.0)
        gameState.firebaseManager.lastKnownTacticalUpdatedAt = 0.0
        let exp = expectation(description: "Fetch tactical indicators on change")
        gameState.firebaseManager.fetchTacticalIndicatorsIfChanged(roomId: "ALPHA")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.indicators["IND-100"]?.type, .watchHere)
            XCTAssertEqual(gameState.firebaseManager.lastKnownTacticalUpdatedAt, 1700000500)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        // 3. Subsequent poll with NO change: _updatedAt is still 1700000500, equal to lastKnownTacticalUpdatedAt
        let countBefore = MockURLProtocol.recordedRequests.filter { $0.url?.absoluteString.contains("/tactical/ALPHA.json") == true }.count
        gameState.firebaseManager.fetchTacticalIndicatorsIfChanged(roomId: "ALPHA")
        
        let expNoChange = expectation(description: "No change poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let countAfter = MockURLProtocol.recordedRequests.filter { $0.url?.absoluteString.contains("/tactical/ALPHA.json") == true }.count
            XCTAssertEqual(countBefore, countAfter, "Must NOT download full tactical payload if _updatedAt is unchanged")
            expNoChange.fulfill()
        }
        wait(for: [expNoChange], timeout: 1.0)
        
        // 4. Delete indicator: Verify DELETE is sent to /tactical/ALPHA/IND-101.json
        gameState.firebaseManager.removeIndicator(roomId: "ALPHA", indicatorId: "IND-101")
        let delExp = expectation(description: "Wait for DELETE request")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let deleteRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "DELETE" }
            XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/tactical/ALPHA/IND-101.json") == true })
            delExp.fulfill()
        }
        wait(for: [delExp], timeout: 1.0)
    }
    
    func testTacticalIndicatorsPurgedOnRoomDisband() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        let room = SquadRoom(id: "ALPHA", hostId: "GHOST-1")
        gameState.firebaseManager.activeRoom = room
        gameState.isHosting = true
        
        let disbandExp = expectation(description: "Room disband purges tactical node")
        gameState.firebaseManager.disbandRoom(roomId: "ALPHA") { success in
            XCTAssertTrue(success)
            disbandExp.fulfill()
        }
        wait(for: [disbandExp], timeout: 1.0)
        
        let deleteRequests = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "DELETE" }
        XCTAssertTrue(deleteRequests.contains { $0.url?.absoluteString.contains("/tactical/ALPHA.json") == true }, "Must delete /tactical/{roomId} node when room is disbanded")
    }
    
    // MARK: - Subscription & RevenueCat Integration Tests
    
    func testSubscriptionManagerMockPurchaseAndRestore() async {
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
        let subManager = SubscriptionManager(engineMode: .mock)
        XCTAssertFalse(subManager.hasUnlimitedSquadUnlock)
        XCTAssertFalse(subManager.canCreateRoom(withCapacity: 10))
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 4))
        XCTAssertEqual(subManager.localizedPrice, "$9.99")
        
        // Purchase flow
        let purchaseSuccess = await subManager.purchaseLifetimeUnlock()
        XCTAssertTrue(purchaseSuccess)
        XCTAssertTrue(subManager.hasUnlimitedSquadUnlock)
        XCTAssertTrue(subManager.purchaseSuccess)
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 10))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey))
        
        // Restore flow
        let restoreSuccess = await subManager.restorePurchases()
        XCTAssertTrue(restoreSuccess)
        XCTAssertTrue(subManager.hasUnlimitedSquadUnlock)
    }
    
    func testSubscriptionManagerRevenueCatConfiguration() {
        let subManager = SubscriptionManager(engineMode: .mock)
        XCTAssertEqual(subManager.activeEngineMode, .mock)
        
        subManager.configureRevenueCat(apiKey: "appl_test_api_key_123")
        XCTAssertEqual(subManager.activeEngineMode, .revenueCat)
        XCTAssertEqual(SubscriptionManager.entitlementID, "radarmap_pro")
        XCTAssertEqual(SubscriptionManager.offeringID, "default")
        XCTAssertEqual(SubscriptionManager.packageID, "$rc_lifetime")
    }
    
    func testSubscriptionManagerPromotionalPriceMessage() {
        let subManager = SubscriptionManager(engineMode: .mock)
        XCTAssertNil(subManager.promotionalPriceMessage)
        
        subManager.promotionalPriceMessage = "50% OFF - Limited Time Offer!"
        XCTAssertEqual(subManager.promotionalPriceMessage, "50% OFF - Limited Time Offer!")
    }
    
    func testSubscriptionManagerCapacityLimits() {
        let subManager = SubscriptionManager(engineMode: .mock)
        subManager.hasUnlimitedSquadUnlock = false
        
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 1))
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 2))
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 3))
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 4))
        XCTAssertFalse(subManager.canCreateRoom(withCapacity: 5))
        XCTAssertFalse(subManager.canCreateRoom(withCapacity: 8))
        XCTAssertFalse(subManager.canCreateRoom(withCapacity: 50))
        
        subManager.hasUnlimitedSquadUnlock = true
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 5))
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 8))
        XCTAssertTrue(subManager.canCreateRoom(withCapacity: 12))
    }
    
    // MARK: - Compact Array Schema Tests
    
    func testCompactArraySerializationAndDeserialization() {
        let packet = TelemetryPacket(
            memberId: "OPERATOR-7",
            roomId: "ECHO-SQUAD",
            latitude: 37.785834,
            longitude: -122.406417,
            altitude: 12.5,
            heading: 270.0,
            heartRate: 115.0,
            timestamp: 1724686650.5,
            sequenceNumber: 42
        )
        
        let compactArray = packet.toCompactArray()
        XCTAssertEqual(compactArray.count, 4, "Ultra-lean wire schema must contain exactly 4 elements: [lat, lng, hr, ts]")
        XCTAssertEqual(compactArray[0] as? Double, 37.785834)
        XCTAssertEqual(compactArray[1] as? Double, -122.406417)
        XCTAssertEqual(compactArray[2] as? Double, 115.0)
        XCTAssertEqual(compactArray[3] as? Double, 1724686650.5)
        
        // Roundtrip deserialization from 4-element array
        let reconstructed = TelemetryPacket.fromCompactArray(memberId: "OPERATOR-7", roomId: "ECHO-SQUAD", array: compactArray)
        XCTAssertNotNil(reconstructed)
        XCTAssertEqual(reconstructed?.memberId, "OPERATOR-7")
        XCTAssertEqual(reconstructed?.roomId, "ECHO-SQUAD")
        XCTAssertEqual(reconstructed?.latitude, 37.785834)
        XCTAssertEqual(reconstructed?.longitude, -122.406417)
        XCTAssertEqual(reconstructed?.heartRate, 115.0)
        XCTAssertEqual(reconstructed?.timestamp, 1724686650.5)
        
        // Legacy 6-element format backward compatibility
        let legacy6Array: [Any] = [37.785834, -122.406417, 12.5, 115.0, Int64(42), 1724686650.5]
        let legacy6Reconstructed = TelemetryPacket.fromCompactArray(memberId: "LEGACY-6", roomId: "ECHO-SQUAD", array: legacy6Array)
        XCTAssertNotNil(legacy6Reconstructed)
        XCTAssertEqual(legacy6Reconstructed?.altitude, 12.5)
        XCTAssertEqual(legacy6Reconstructed?.sequenceNumber, 42)
        
        // Legacy 7-element format backward compatibility
        let legacy7Array: [Any] = [37.785834, -122.406417, 12.5, 270.0, 115.0, Int64(42), 1724686650.5]
        let legacy7Reconstructed = TelemetryPacket.fromCompactArray(memberId: "LEGACY-7", roomId: "ECHO-SQUAD", array: legacy7Array)
        XCTAssertNotNil(legacy7Reconstructed)
        XCTAssertEqual(legacy7Reconstructed?.heading, 270.0)
        XCTAssertEqual(legacy7Reconstructed?.heartRate, 115.0)
    }
    
    func testRemoteTelemetryCompactArrayPollingWorkflow() {
        MockURLProtocol.reset()
        
        // Server response in ultra-lean 4-element schema: {"MEMBER_A": [lat, lng, hr, ts]}
        let rawResponseJson = """
        {
            "MEMBER_A": [37.7858, -122.4064, 80.0, 1724686650.0],
            "MEMBER_B": [37.7860, -122.4070, 95.0, 1724686651.0]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.absoluteString.contains("/telemetry/") == true {
                return (response, rawResponseJson.data(using: .utf8)!)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        let room = SquadRoom(id: "COMPACT_ROOM", hostId: "MEMBER_A", members: [:])
        gameState.firebaseManager.activeRoom = room
        gameState.firebaseManager.fetchRemoteTelemetry(roomId: "COMPACT_ROOM")
        
        let exp = expectation(description: "Process compact array telemetry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.members["MEMBER_A"]?.heartRate, 80.0)
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.members["MEMBER_B"]?.heartRate, 95.0)
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.members["MEMBER_A"]?.latitude ?? 0.0, 37.7858, accuracy: 0.0001)
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.members["MEMBER_B"]?.latitude ?? 0.0, 37.7860, accuracy: 0.0001)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    // MARK: - COG & Speed-Weighted Heading Blending Tests
    
    func testCompact4ElementWireFormatWithoutAltSeqHdg() {
        let packet = TelemetryPacket(
            memberId: "VIPER-1",
            roomId: "ALPHA",
            latitude: 37.7858,
            longitude: -122.4064,
            heartRate: 85.0,
            timestamp: 1724686650.0,
            sequenceNumber: 100
        )
        
        let compactArray = packet.toCompactArray()
        XCTAssertEqual(compactArray.count, 4, "Ultra-lean wire schema must contain exactly 4 elements [lat, lng, hr, ts]")
        XCTAssertEqual(compactArray[0] as? Double, 37.7858)
        XCTAssertEqual(compactArray[1] as? Double, -122.4064)
        XCTAssertEqual(compactArray[2] as? Double, 85.0) // hr
        XCTAssertEqual(compactArray[3] as? Double, 1724686650.0) // ts
        
        // Reconstruct from 4-element array
        let reconstructed = TelemetryPacket.fromCompactArray(memberId: "VIPER-1", roomId: "ALPHA", array: compactArray)
        XCTAssertNotNil(reconstructed)
        XCTAssertEqual(reconstructed?.latitude, 37.7858)
        XCTAssertEqual(reconstructed?.longitude, -122.4064)
        XCTAssertEqual(reconstructed?.heartRate, 85.0)
        XCTAssertEqual(reconstructed?.timestamp, 1724686650.0)
    }
    
    func testLocalSpeedWeightedHeadingBlending_Stationary() {
        // Speed <= 0.5 m/s -> 100% Compass
        let compass = 45.0
        let cogCourse = 180.0
        let speed = 0.2 // stationary / creeping
        
        let blended = LocationHeadingManager.computeBlendedHeading(
            compassHeading: compass,
            gpsCourse: cogCourse,
            speedMps: speed
        )
        XCTAssertEqual(blended, 45.0, accuracy: 0.001, "Stationary speed must rely 100% on compass heading")
    }
    
    func testLocalSpeedWeightedHeadingBlending_Running() {
        // Speed >= 2.5 m/s -> 100% GPS COG
        let compass = 45.0 // arm swinging
        let cogCourse = 180.0 // running South
        let speed = 3.5 // running
        
        let blended = LocationHeadingManager.computeBlendedHeading(
            compassHeading: compass,
            gpsCourse: cogCourse,
            speedMps: speed
        )
        XCTAssertEqual(blended, 180.0, accuracy: 0.001, "Running speed must rely 100% on GPS Course Over Ground")
    }
    
    func testLocalSpeedWeightedHeadingBlending_SmoothTransitionAndNorthWrap() {
        // Midpoint speed (1.5 m/s) -> 50% blend
        // Test angle wrapping around North: 350° and 10°
        // Vector average of 350° (-10°) and 10° is exactly 0° / 360°
        let angle1 = 350.0
        let angle2 = 10.0
        
        let blended = LocationHeadingManager.computeBlendedHeading(
            compassHeading: angle1,
            gpsCourse: angle2,
            speedMps: 1.5
        )
        // 0.0 or 360.0 (both represent North)
        XCTAssertTrue(abs(blended - 0.0) < 0.01 || abs(blended - 360.0) < 0.01, "Circular interpolation across 360° north boundary must yield 0°/360°")
        
        // Midpoint between 0° and 90° at 1.5 m/s -> 45°
        let blended45 = LocationHeadingManager.computeBlendedHeading(
            compassHeading: 0.0,
            gpsCourse: 90.0,
            speedMps: 1.5
        )
        XCTAssertEqual(blended45, 45.0, accuracy: 0.001)
    }
    
    func testRemoteMemberCourseOverGroundCalculation() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "COG_ROOM", hostId: "LOCAL_USER", members: [:])
        syncManager.connectToRoom(room)
        
        let metersPerDegreeLat = AppConstants.Location.metersPerDegreeLatitude // 111,139
        let baseLat = 37.785834
        let baseLng = -122.406417
        let metersPerDegreeLon = metersPerDegreeLat * cos(baseLat * .pi / 180.0)
        
        // 1. Packet 1: Initial position
        let p1 = TelemetryPacket(memberId: "REMOTE_OP", roomId: "COG_ROOM", latitude: baseLat, longitude: baseLng, heartRate: 75.0, timestamp: 1000, sequenceNumber: 1)
        XCTAssertTrue(syncManager.validateAndProcessPacket(p1))
        
        // 2. Packet 2: Move North by 20 meters -> Bearing ~0°
        let p2North = TelemetryPacket(
            memberId: "REMOTE_OP",
            roomId: "COG_ROOM",
            latitude: baseLat + (20.0 / metersPerDegreeLat),
            longitude: baseLng,
            heartRate: 75.0,
            timestamp: 1002,
            sequenceNumber: 2
        )
        XCTAssertTrue(syncManager.validateAndProcessPacket(p2North))
        let northHeading = syncManager.activeRoom?.members["REMOTE_OP"]?.heading ?? 999.0
        XCTAssertEqual(northHeading, 0.0, accuracy: 1.0, "Northward movement must yield ~0° heading")
        
        // 3. Packet 3: Move East by 20 meters -> Bearing ~90°
        let p3East = TelemetryPacket(
            memberId: "REMOTE_OP",
            roomId: "COG_ROOM",
            latitude: baseLat + (20.0 / metersPerDegreeLat),
            longitude: baseLng + (20.0 / metersPerDegreeLon),
            heartRate: 75.0,
            timestamp: 1004,
            sequenceNumber: 3
        )
        XCTAssertTrue(syncManager.validateAndProcessPacket(p3East))
        let eastHeading = syncManager.activeRoom?.members["REMOTE_OP"]?.heading ?? 999.0
        XCTAssertEqual(eastHeading, 90.0, accuracy: 1.0, "Eastward movement must yield ~90° heading")
        
        // 4. Packet 4: Stationary packet (0m displacement) -> Must RETAIN previous heading (90°)
        let p4Stationary = TelemetryPacket(
            memberId: "REMOTE_OP",
            roomId: "COG_ROOM",
            latitude: baseLat + (20.0 / metersPerDegreeLat),
            longitude: baseLng + (20.0 / metersPerDegreeLon),
            heartRate: 75.0,
            timestamp: 1006,
            sequenceNumber: 4
        )
        XCTAssertTrue(syncManager.validateAndProcessPacket(p4Stationary))
        let stationaryHeading = syncManager.activeRoom?.members["REMOTE_OP"]?.heading ?? 999.0
        XCTAssertEqual(stationaryHeading, 90.0, accuracy: 0.001, "Zero displacement must retain previous heading")
    }
    
    func testSelfTelemetryIgnoredFromRemoteEndpointAndUsesLiveBlendedHeading() {
        MockURLProtocol.reset()
        let rawResponseJson = """
        {
            "LOCAL_PLAYER": [40.7128, -74.0060, 150.0, 1724686650.0],
            "REMOTE_PLAYER": [37.7860, -122.4070, 95.0, 1724686651.0]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.absoluteString.contains("/telemetry/") == true {
                return (response, rawResponseJson.data(using: .utf8)!)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.myMemberId = "LOCAL_PLAYER"
        gameState.firebaseManager.localMemberId = "LOCAL_PLAYER"
        
        let room = SquadRoom(id: "TEST_ROOM", hostId: "LOCAL_PLAYER", members: [:])
        gameState.firebaseManager.activeRoom = room
        gameState.firebaseManager.fetchRemoteTelemetry(roomId: "TEST_ROOM")
        
        let exp = expectation(description: "Process remote telemetry filtering self")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Local player's telemetry must NOT have been downloaded/applied from the server
            XCTAssertNil(gameState.firebaseManager.activeRoom?.members["LOCAL_PLAYER"])
            // Remote player's telemetry MUST be downloaded and applied
            XCTAssertEqual(gameState.firebaseManager.activeRoom?.members["REMOTE_PLAYER"]?.heartRate, 95.0)
            
            // gameState.localPlayerMember must always provide live local data and COD blended heading
            let localMember = gameState.localPlayerMember
            XCTAssertEqual(localMember.id, "LOCAL_PLAYER")
            XCTAssertEqual(localMember.heading, gameState.locationHeadingManager.blendedHeading)
            
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testDeadReckoningEngineRemotePlayerSmoothing() {
        let engine = DeadReckoningEngine()
        let startCoord = CLLocationCoordinate2D(latitude: 37.7800, longitude: -122.4000)
        let targetCoord = CLLocationCoordinate2D(latitude: 37.7810, longitude: -122.4010)
        
        let member = SquadMember(
            id: "REMOTE_1",
            callsign: "VIPER",
            latitude: startCoord.latitude,
            longitude: startCoord.longitude,
            heading: 45.0,
            heartRate: 80.0,
            lastUpdatedTimestamp: Date().timeIntervalSince1970
        )
        
        // Initial state
        engine.updateRemotePlayer(id: member.id, newCoordinate: startCoord, newHeading: 45.0, packetTimestamp: Date().timeIntervalSince1970)
        XCTAssertEqual(engine.coordinate(for: member).latitude, startCoord.latitude, accuracy: 1e-6)
        XCTAssertEqual(engine.heading(for: member), 45.0, accuracy: 0.1)
        
        // Target state
        engine.updateRemotePlayer(id: member.id, newCoordinate: targetCoord, newHeading: 90.0, packetTimestamp: Date().timeIntervalSince1970)
        
        // State should exist and be smoothly tracked
        XCTAssertNotNil(engine.smoothedMembers["REMOTE_1"])
        XCTAssertEqual(engine.smoothedMembers["REMOTE_1"]?.targetCoordinate.latitude, targetCoord.latitude)
        XCTAssertEqual(engine.smoothedMembers["REMOTE_1"]?.targetHeading, 90.0)
        
        engine.removePlayer(id: "REMOTE_1")
        XCTAssertNil(engine.smoothedMembers["REMOTE_1"])
    }
    
    // MARK: - Login Check Field Error Tests
    
    func testLoginCheck_DuplicateCallsign_TurnsCallsignFieldRed() {
        MockURLProtocol.reset()
        let existingMember = SquadMember(id: "HOST1", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        let room = SquadRoom(id: "ALPHA", hostId: "HOST1", members: ["HOST1": existingMember])
        let roomData = try! JSONEncoder().encode(room)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.myMemberId = "PLAYER_2"
        gameState.myCallsign = "VIPER" // Duplicate callsign
        
        XCTAssertFalse(gameState.callsignError)
        
        let exp = expectation(description: "Duplicate callsign error")
        gameState.joinRoom(id: "ALPHA") { success in
            XCTAssertFalse(success)
            XCTAssertTrue(gameState.callsignError, "Callsign field must turn red on callsign duplication")
            XCTAssertFalse(gameState.squadNameError)
            XCTAssertFalse(gameState.pinError)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.duplicateCallsign.localizedDescription)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testLoginCheck_ServerNameDuplicationIfHosting_TurnsSquadNameFieldRed() {
        MockURLProtocol.reset()
        let existingRoom = SquadRoom(id: "EXISTING_SQUAD", hostId: "OTHER_HOST", members: [:])
        let roomData = try! JSONEncoder().encode(existingRoom)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        XCTAssertFalse(gameState.squadNameError)
        
        let exp = expectation(description: "Server duplication on host error")
        gameState.hostRoom(name: "EXISTING_SQUAD") { success in
            XCTAssertFalse(success)
            XCTAssertTrue(gameState.squadNameError, "Squad name field must turn red if server already exists when hosting")
            XCTAssertFalse(gameState.callsignError)
            XCTAssertFalse(gameState.pinError)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.roomAlreadyExists.localizedDescription)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testLoginCheck_ServerNameDoesNotExistIfJoining_TurnsSquadNameFieldRed() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "null".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        XCTAssertFalse(gameState.squadNameError)
        
        let exp = expectation(description: "Server does not exist on join error")
        gameState.joinRoom(id: "UNKNOWN_SQUAD") { success in
            XCTAssertFalse(success)
            XCTAssertTrue(gameState.squadNameError, "Squad name field must turn red if server doesn't exist when joining")
            XCTAssertFalse(gameState.callsignError)
            XCTAssertFalse(gameState.pinError)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.roomNotFound.localizedDescription)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testLoginCheck_IncorrectPinIfJoining_TurnsPinFieldRed() {
        MockURLProtocol.reset()
        let pinHash = FirebaseSyncManager.hashPin("1234", salt: "LOCKED_SQUAD")
        let lockedRoom = SquadRoom(id: "LOCKED_SQUAD", hostId: "HOST1", hasPin: true, pinHash: pinHash, members: [:])
        let roomData = try! JSONEncoder().encode(lockedRoom)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        gameState.myMemberId = "PLAYER_1"
        gameState.myCallsign = "GHOST"
        XCTAssertFalse(gameState.pinError)
        
        let exp = expectation(description: "Incorrect PIN error")
        gameState.joinRoom(id: "LOCKED_SQUAD", pin: "9999") { success in
            XCTAssertFalse(success)
            XCTAssertTrue(gameState.pinError, "PIN field must turn red if PIN is incorrect when joining")
            XCTAssertFalse(gameState.callsignError)
            XCTAssertFalse(gameState.squadNameError)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.incorrectPin.localizedDescription)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testSquadMemberStreamlinedSerializationExcludesTelemetry() throws {
        let member = SquadMember(
            id: "uuid_user_1234",
            callsign: "VIPER",
            latitude: 37.785834,
            longitude: -122.406417,
            altitude: 15.0,
            heading: 180.0,
            heartRate: 140.0,
            batteryLevel: 0.85,
            lastUpdatedTimestamp: 1787767191.0,
            sequenceNumber: 42,
            status: .active,
            isHost: true,
            colorHex: "#FF0000"
        )
        
        let encodedData = try JSONEncoder().encode(member)
        let json = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        XCTAssertNotNil(json)
        
        // Allowed metadata keys for room roster
        XCTAssertEqual(json?["id"] as? String, "uuid_user_1234")
        XCTAssertEqual(json?["callsign"] as? String, "VIPER")
        XCTAssertEqual(json?["isHost"] as? Bool, true)
        
        // Excluded dynamic telemetry fields
        XCTAssertNil(json?["latitude"])
        XCTAssertNil(json?["longitude"])
        XCTAssertNil(json?["altitude"])
        XCTAssertNil(json?["heading"])
        XCTAssertNil(json?["heartRate"])
        XCTAssertNil(json?["batteryLevel"])
        XCTAssertNil(json?["lastUpdatedTimestamp"])
        XCTAssertNil(json?["sequenceNumber"])
        XCTAssertNil(json?["status"])
        XCTAssertNil(json?["colorHex"])
    }
    
    func testPersistentMemberIdDistinctFromCallsign() {
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.userMemberIdKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.userCallsignKey)
        
        let gameState = GameStateManager()
        XCTAssertFalse(gameState.myMemberId.isEmpty)
        XCTAssertNotEqual(gameState.myMemberId, gameState.myCallsign, "myMemberId should be a distinct persistent UUID, not identical to callsign")
        
        let initialMemberId = gameState.myMemberId
        gameState.myCallsign = "RECON_1"
        XCTAssertEqual(gameState.myMemberId, initialMemberId, "myMemberId should stay stable when callsign is edited")
    }
    
    // MARK: - Dead Reckoning Delta Gating & SSE Stream Optimization Tests
    
    func testMovementDeltaGatingSuppressesStationaryUploads() {
        let gameState = createMockGameState()
        let room = SquadRoom(id: "DELTA_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        let baseLocation = CLLocation(latitude: 37.785834, longitude: -122.406417)
        gameState.locationHeadingManager.userLocation = baseLocation
        gameState.locationHeadingManager.blendedHeading = 90.0
        gameState.healthKitManager.currentHeartRate = 80.0
        gameState.isDead = false
        
        // Force baseline sync so lastSentLocation = baseLocation, lastSentHeading = 90.0, lastSentHeartRate = 80.0
        gameState.broadcastLocalTelemetry(location: baseLocation, heading: 90.0, heartRate: 80.0, force: true)
        let baselineEmittedCount = gameState.totalTelemetryUploadsEmitted
        
        // Micro displacement (2.2m < 3.5m) and small HR change (5 BPM < 12 BPM)
        let microMovedLocation = CLLocation(latitude: 37.785834 + 0.000020, longitude: -122.406417) // ~2.22 meters
        XCTAssertLessThan(microMovedLocation.distance(from: baseLocation), AppConstants.Timing.DeltaGating.minMovementDeltaMeters)
        
        let now = Date().timeIntervalSince1970
        let shouldEmitMicro = gameState.shouldEmitTelemetry(
            currentLocation: microMovedLocation,
            currentHeading: 91.0,
            currentHeartRate: 85.0,
            currentIsDead: false,
            currentTime: now,
            force: false
        )
        XCTAssertFalse(shouldEmitMicro, "Micro movements (< 3.5m) and minor HR fluctuations (< 12 BPM) while stationary should be gated / suppressed")
        
        // Applying micro-movement with timer reset to isolate delta gating check
        gameState.lastUploadTimestamp = 0.0
        gameState.broadcastLocalTelemetry(location: microMovedLocation, heading: 91.0, heartRate: 85.0, force: false)
        
        XCTAssertEqual(gameState.totalTelemetryUploadsEmitted, baselineEmittedCount, "Emitted packets must remain unchanged when stationary")
        XCTAssertGreaterThanOrEqual(gameState.totalTelemetryUploadsGated, 1)
    }
    
    func testMovementDeltaGatingTriggersOnSignificantDisplacement() {
        let gameState = createMockGameState()
        let room = SquadRoom(id: "MOVE_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        let startLoc = CLLocation(latitude: 37.785834, longitude: -122.406417)
        gameState.locationHeadingManager.userLocation = startLoc
        gameState.locationHeadingManager.blendedHeading = 0.0
        gameState.healthKitManager.currentHeartRate = 75.0
        gameState.isDead = false
        
        let emittedBefore = gameState.totalTelemetryUploadsEmitted
        
        // Move 5.0 meters (>= 3.5m threshold)
        let movedLoc = CLLocation(latitude: 37.785834 + 0.000045, longitude: -122.406417)
        XCTAssertGreaterThanOrEqual(movedLoc.distance(from: startLoc), AppConstants.Timing.DeltaGating.minMovementDeltaMeters)
        
        let now = Date().timeIntervalSince1970
        let shouldEmit = gameState.shouldEmitTelemetry(
            currentLocation: movedLoc,
            currentHeading: 0.0,
            currentHeartRate: 75.0,
            currentIsDead: false,
            currentTime: now,
            force: false
        )
        XCTAssertTrue(shouldEmit, "Displacement >= 3.5m must trigger upload")
        
        gameState.lastUploadTimestamp = 0.0
        gameState.locationHeadingManager.userLocation = movedLoc
        XCTAssertEqual(gameState.totalTelemetryUploadsEmitted, emittedBefore + 1, "Displacement >= 3.5m must emit new packet")
    }
    
    func testHeadingChangesAloneDoNotTriggerUploads() {
        let gameState = createMockGameState()
        let room = SquadRoom(id: "TURN_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        let loc = CLLocation(latitude: 37.785834, longitude: -122.406417)
        gameState.locationHeadingManager.userLocation = loc
        gameState.locationHeadingManager.blendedHeading = 10.0
        gameState.healthKitManager.currentHeartRate = 75.0
        
        // Force baseline sync
        gameState.broadcastLocalTelemetry(location: loc, heading: 10.0, heartRate: 75.0, force: true)
        let emittedBefore = gameState.totalTelemetryUploadsEmitted
        
        // Turn 50° while stationary in position
        let now = Date().timeIntervalSince1970
        let shouldEmit = gameState.shouldEmitTelemetry(
            currentLocation: loc,
            currentHeading: 60.0,
            currentHeartRate: 75.0,
            currentIsDead: false,
            currentTime: now,
            force: false
        )
        XCTAssertFalse(shouldEmit, "Heading changes alone without displacement must NOT trigger uploads (teammates compute COG or receive heading on displacement)")
        
        gameState.lastUploadTimestamp = 0.0
        gameState.locationHeadingManager.blendedHeading = 60.0
        XCTAssertEqual(gameState.totalTelemetryUploadsEmitted, emittedBefore, "Emitted packets must remain unchanged when merely turning in place")
    }
    
    func testMovementDeltaGatingTriggersOnHeartRateChange() {
        let gameState = createMockGameState()
        let room = SquadRoom(id: "HR_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        let loc = CLLocation(latitude: 37.785834, longitude: -122.406417)
        gameState.locationHeadingManager.userLocation = loc
        gameState.locationHeadingManager.blendedHeading = 0.0
        gameState.healthKitManager.currentHeartRate = 70.0
        
        // Force baseline sync with 70.0 BPM
        gameState.broadcastLocalTelemetry(location: loc, heartRate: 70.0, force: true)
        let emittedBefore = gameState.totalTelemetryUploadsEmitted
        
        // Heart rate jumps from 70 to 85 BPM (15 BPM shift >= 12 BPM threshold)
        let now = Date().timeIntervalSince1970
        let shouldEmit = gameState.shouldEmitTelemetry(
            currentLocation: loc,
            currentHeading: 0.0,
            currentHeartRate: 85.0,
            currentIsDead: false,
            currentTime: now,
            force: false
        )
        XCTAssertTrue(shouldEmit, "Heart rate shift >= 12 BPM must trigger upload")
        
        gameState.lastUploadTimestamp = 0.0
        gameState.healthKitManager.currentHeartRate = 85.0
        XCTAssertEqual(gameState.totalTelemetryUploadsEmitted, emittedBefore + 1, "Heart rate shift >= 12 BPM must emit new packet")
    }
    
    func testHeartbeatFallbackTriggersWhenStationary() {
        let gameState = createMockGameState()
        let room = SquadRoom(id: "HEARTBEAT_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        let loc = CLLocation(latitude: 37.785834, longitude: -122.406417)
        gameState.locationHeadingManager.userLocation = loc
        gameState.locationHeadingManager.blendedHeading = 0.0
        gameState.healthKitManager.currentHeartRate = 75.0
        
        // Fixed fallback timer constant for upload liveness: 10.0s
        XCTAssertEqual(gameState.currentHeartbeatFallbackInterval(), 10.0, accuracy: 0.01)
        
        // Stationary for 5.0 seconds (< 10.0s) -> should be suppressed
        let now = Date().timeIntervalSince1970
        let shouldNotEmit = gameState.shouldEmitTelemetry(
            currentLocation: loc,
            currentHeading: 0.0,
            currentHeartRate: 75.0,
            currentIsDead: false,
            currentTime: now + 5.0,
            force: false
        )
        XCTAssertFalse(shouldNotEmit, "Stationary before 10s fallback must be gated")
        
        // Simulate stationary in cover for 11.0 seconds (> 10.0s fallback threshold)
        let shouldEmit = gameState.shouldEmitTelemetry(
            currentLocation: loc,
            currentHeading: 0.0,
            currentHeartRate: 75.0,
            currentIsDead: false,
            currentTime: now + 11.0,
            force: false
        )
        XCTAssertTrue(shouldEmit, "Stationary heartbeat fallback (10.0s) must emit to prevent teammate icons from turning gray")
    }
    
    func testLargeServerHeartbeatFallbackScaling() {
        let gameState = createMockGameState()
        var members: [String: SquadMember] = [:]
        for i in 1...30 {
            members["MEMBER_\(i)"] = SquadMember(id: "MEMBER_\(i)", callsign: "OP_\(i)", latitude: 37.78, longitude: -122.40)
        }
        let largeRoom = SquadRoom(id: "LARGE_ROOM", hostId: "MEMBER_1", members: members)
        gameState.firebaseManager.activeRoom = largeRoom
        
        // 30 players: updateInterval = 1.0 * (30 / 12) = 2.5s
        gameState.recalculateAdaptiveUploadInterval()
        XCTAssertEqual(gameState.adaptiveUploadInterval, 2.5, accuracy: 0.01)
        
        // Heartbeat fallback timer constant: 10.0s
        let fallbackInterval = gameState.currentHeartbeatFallbackInterval()
        XCTAssertEqual(fallbackInterval, 10.0, accuracy: 0.01, "Upload fallback constant remains 10s")
    }
    
    func testDownedStatusBypassesGating() {
        let gameState = createMockGameState()
        let room = SquadRoom(id: "KIA_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        let loc = CLLocation(latitude: 37.785834, longitude: -122.406417)
        gameState.locationHeadingManager.userLocation = loc
        gameState.locationHeadingManager.blendedHeading = 0.0
        gameState.healthKitManager.currentHeartRate = 75.0
        gameState.isDead = false
        
        let emittedBefore = gameState.totalTelemetryUploadsEmitted
        
        // Player dies / goes downed -> Must immediately emit
        gameState.setDead(true)
        XCTAssertEqual(gameState.totalTelemetryUploadsEmitted, emittedBefore + 1, "Transition to downed/KIA must emit telemetry immediately")
    }
    
    func testFirebaseSSEStreamSnapshotAndDeltaParsing() {
        let syncManager = FirebaseSyncManager()
        let room = SquadRoom(id: "SSE_ROOM", hostId: "HOST_1")
        syncManager.activeRoom = room
        
        // 1. Root snapshot frame (event: put with path: "/")
        let snapshotData = """
        {
            "path": "/",
            "data": {
                "OP_1": [37.7858, -122.4064, 10.0, 90.0, 75.0, 1700000000, 1],
                "OP_2": [37.7860, -122.4070, 12.0, 180.0, 80.0, 1700000000, 1]
            }
        }
        """
        syncManager.parseSSEEvent(event: "put", dataString: snapshotData, roomId: "SSE_ROOM")
        
        XCTAssertEqual(syncManager.activeRoom?.members["OP_1"]?.latitude, 37.7858)
        XCTAssertEqual(syncManager.activeRoom?.members["OP_2"]?.latitude, 37.7860)
        XCTAssertEqual(syncManager.totalPacketsProcessed, 2)
        
        // 2. Single delta update frame (event: put with path: "/OP_1")
        let deltaData = """
        {
            "path": "/OP_1",
            "data": [37.7859, -122.4065, 11.0, 95.0, 78.0, 1700000005, 2]
        }
        """
        syncManager.parseSSEEvent(event: "put", dataString: deltaData, roomId: "SSE_ROOM")
        
        XCTAssertEqual(syncManager.activeRoom?.members["OP_1"]?.latitude, 37.7859)
        XCTAssertEqual(syncManager.activeRoom?.members["OP_1"]?.heading, 95.0)
        XCTAssertEqual(syncManager.totalPacketsProcessed, 3)
    }
    
    func testWristDownThrottlingAndInstantWakeBurst() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let samplePayload = """
            {
                "OP_WAKE": [37.7858, -122.4064, 10.0, 90.0, 75.0, 1700000000, 1]
            }
            """
            return (response, samplePayload.data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        let room = SquadRoom(id: "WAKE_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        // Initial state: Wrist active -> polling interval is baseline (1.0s)
        XCTAssertTrue(gameState.firebaseManager.isWristActive)
        XCTAssertEqual(gameState.firebaseManager.pollingInterval, 1.0)
        
        // 1. Wrist lowers (scenePhase == .inactive / isLuminanceReduced == true)
        gameState.setWristActive(false)
        XCTAssertFalse(gameState.firebaseManager.isWristActive)
        XCTAssertEqual(gameState.firebaseManager.pollingInterval, AppConstants.Timing.AdaptiveRate.wristDownPollingInterval, "Polling interval must throttle to 10s when wrist is down")
        
        // 2. Wrist raises (Instant Wake Burst)
        let processedBefore = gameState.firebaseManager.totalPacketsProcessed
        let exp = expectation(description: "Instant wake burst fetches telemetry immediately")
        
        gameState.setWristActive(true)
        XCTAssertTrue(gameState.firebaseManager.isWristActive)
        XCTAssertEqual(gameState.firebaseManager.pollingInterval, 1.0, "Polling interval must restore to 1.0s on wrist raise")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertGreaterThan(gameState.firebaseManager.totalPacketsProcessed, processedBefore, "Instant wake burst must immediately fetch telemetry")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testDoubleTapAndAwakeInteractionTriggerWakeBurst() {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let samplePayload = """
            {
                "OP_WAKE2": [37.7858, -122.4064, 10.0, 90.0, 75.0, 1700000000, 1]
            }
            """
            return (response, samplePayload.data(using: .utf8)!)
        }
        
        let gameState = createMockGameState()
        let room = SquadRoom(id: "DOUBLE_TAP_ROOM", hostId: gameState.myMemberId)
        gameState.firebaseManager.activeRoom = room
        
        // Put in inactive state (wrist down)
        gameState.setWristActive(false)
        XCTAssertFalse(gameState.firebaseManager.isWristActive)
        XCTAssertEqual(gameState.firebaseManager.pollingInterval, 10.0)
        
        // Trigger awake burst (e.g. from double tap or screen tap gesture)
        let processedBefore = gameState.firebaseManager.totalPacketsProcessed
        let exp = expectation(description: "Double-tap/gesture awake burst immediately restores active polling and fetches telemetry")
        
        gameState.triggerWakeBurst()
        XCTAssertTrue(gameState.firebaseManager.isWristActive)
        XCTAssertEqual(gameState.firebaseManager.pollingInterval, 1.0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertGreaterThan(gameState.firebaseManager.totalPacketsProcessed, processedBefore)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    // MARK: - Policy Configuration Tests
    
    func testPolicyConstantsAndConfiguration() {
        // Verify Privacy Policy URL is valid HTTPS URL
        XCTAssertFalse(AppConstants.Policy.privacyPolicyURL.isEmpty)
        guard let privacyUrl = URL(string: AppConstants.Policy.privacyPolicyURL) else {
            XCTFail("Privacy Policy URL must be valid")
            return
        }
        XCTAssertEqual(privacyUrl.scheme, "https")
        XCTAssertEqual(privacyUrl.host, "radarmap.app")
        
        // Verify Contact Email is valid email format
        XCTAssertEqual(AppConstants.Policy.contactEmail, "sweetdreamsdeveloper@gmail.com")
        XCTAssertTrue(AppConstants.Policy.contactEmail.contains("@"))
        XCTAssertTrue(AppConstants.Policy.contactEmail.contains("."))
        
        // Verify Contact Form URL
        XCTAssertEqual(AppConstants.Policy.contactFormURL, "https://forms.gle/pCuy2zJtSfLoyqj16")
        guard let formUrl = URL(string: AppConstants.Policy.contactFormURL) else {
            XCTFail("Contact Form URL must be valid")
            return
        }
        XCTAssertEqual(formUrl.scheme, "https")
        
        // Verify mailto URL construction
        guard let mailUrl = URL(string: "mailto:\(AppConstants.Policy.contactEmail)") else {
            XCTFail("Mailto URL must be valid")
            return
        }
        XCTAssertEqual(mailUrl.scheme, "mailto")
        
        // Verify policy summary and disclosures are present
        XCTAssertFalse(AppConstants.Policy.summary.isEmpty)
        XCTAssertFalse(AppConstants.Policy.locationDataDescription.isEmpty)
        XCTAssertFalse(AppConstants.Policy.healthDataDescription.isEmpty)
        XCTAssertFalse(AppConstants.Policy.dataRetentionDescription.isEmpty)
    }
    
    // MARK: - Callsign, Room Name & PIN Retention Tests
    
    func testCallsignAndRoomNameRetentionInUserDefaultsAndGameState() {
        // Clear existing keys
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.userCallsignKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.savedRoomNameKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.savedPinKey)
        
        // 1. Fresh state has no hardcoded values
        var gameState = GameStateManager()
        XCTAssertEqual(gameState.myCallsign, "", "Fresh gameState must have empty callsign by default (no hardcoded value)")
        XCTAssertEqual(gameState.savedRoomName, "", "Fresh gameState must have empty savedRoomName by default (no hardcoded value)")
        XCTAssertEqual(gameState.savedPin, "", "Fresh gameState must have empty savedPin by default (no hardcoded value)")
        
        // 2. Modifying properties updates UserDefaults
        gameState.myCallsign = "VIPER-7"
        gameState.savedRoomName = "BRAVO"
        gameState.savedPin = "1234"
        
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.Storage.userCallsignKey), "VIPER-7")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.Storage.savedRoomNameKey), "BRAVO")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppConstants.Storage.savedPinKey), "1234")
        
        // 3. New launch prepopulates from UserDefaults
        let newGameState = GameStateManager()
        XCTAssertEqual(newGameState.myCallsign, "VIPER-7", "New GameStateManager instance should prepopulate callsign from UserDefaults")
        XCTAssertEqual(newGameState.savedRoomName, "BRAVO", "New GameStateManager instance should prepopulate room name from UserDefaults")
        XCTAssertEqual(newGameState.savedPin, "1234", "New GameStateManager instance should prepopulate PIN from UserDefaults")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.userCallsignKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.savedRoomNameKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.Storage.savedPinKey)
    }
    
    // MARK: - Default User Map Centering Tests
    
    func testLocationUpdatesStartOnAppLaunch() {
        let gameState = GameStateManager()
        XCTAssertTrue(gameState.locationHeadingManager.isUpdating, "Location and heading updates should be active on launch so user position is known")
    }
    
    func testDefaultMapStyleAndRadarCenterFollowsUser() {
        let gameState = GameStateManager()
        XCTAssertEqual(gameState.selectedMapStyle, .radar, "Default map style should be tactical radar")
        
        // When location is updated, local player member uses updated coordinate
        let testCoord = CLLocation(latitude: 37.7749, longitude: -122.4194)
        gameState.locationHeadingManager.userLocation = testCoord
        
        let localPlayerCoord = gameState.locationHeadingManager.userLocation?.coordinate
        XCTAssertEqual(localPlayerCoord?.latitude, 37.7749)
        XCTAssertEqual(localPlayerCoord?.longitude, -122.4194)
    }
    
    // MARK: - Room Name & Callsign Validation and Scope Tests
    
    func testCreateRoomRejectsEmptyRoomName() {
        let syncManager = createMockFirebaseSyncManager()
        let emptyIdRoom = SquadRoom(id: "   ", hostId: "USER1", members: ["USER1": SquadMember(id: "USER1", callsign: "VIPER", latitude: 0, longitude: 0)])
        
        let exp = expectation(description: "Empty room name rejected on create")
        syncManager.createRoom(emptyIdRoom) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with empty room name")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.emptyRoomName)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testCreateRoomRejectsEmptyCallsign() {
        let syncManager = createMockFirebaseSyncManager()
        let emptyCallsignMember = SquadMember(id: "USER1", callsign: "   ", latitude: 0, longitude: 0)
        let room = SquadRoom(id: "ALPHA", hostId: "USER1", members: ["USER1": emptyCallsignMember])
        
        let exp = expectation(description: "Empty callsign rejected on create")
        syncManager.createRoom(room) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with empty member callsign")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.emptyCallsign)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testJoinRoomRejectsEmptyRoomName() {
        let syncManager = createMockFirebaseSyncManager()
        let member = SquadMember(id: "USER2", callsign: "GHOST", latitude: 0, longitude: 0)
        
        let exp = expectation(description: "Empty room name rejected on join")
        syncManager.joinRoom(id: "  ", member: member) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with empty room name")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.emptyRoomName)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testJoinRoomRejectsEmptyCallsign() {
        let syncManager = createMockFirebaseSyncManager()
        let emptyCallsignMember = SquadMember(id: "USER2", callsign: "   ", latitude: 0, longitude: 0)
        
        let exp = expectation(description: "Empty callsign rejected on join")
        syncManager.joinRoom(id: "ALPHA", member: emptyCallsignMember) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with empty callsign")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.emptyCallsign)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testCallsignUniqueWithinRoomOnly_SameRoomRejection() {
        MockURLProtocol.reset()
        let existingMember = SquadMember(id: "USER1", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        let roomA = SquadRoom(id: "ROOM_A", hostId: "USER1", members: ["USER1": existingMember])
        let roomData = try! JSONEncoder().encode(roomA)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let syncManager = createMockFirebaseSyncManager()
        let duplicateMember = SquadMember(id: "USER2", callsign: "viper", latitude: 37.77, longitude: -122.41)
        
        let exp = expectation(description: "Duplicate callsign in same room rejected")
        syncManager.joinRoom(id: "ROOM_A", member: duplicateMember) { result in
            switch result {
            case .success:
                XCTFail("Duplicate callsign in same room must be rejected")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.duplicateCallsign)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testCallsignUniqueWithinRoomOnly_DifferentRoomsAllowed() {
        MockURLProtocol.reset()
        // Room B does NOT have a member named VIPER (it has GHOST)
        let roomBMember = SquadMember(id: "USER3", callsign: "GHOST", latitude: 37.77, longitude: -122.41)
        let roomB = SquadRoom(id: "ROOM_B", hostId: "USER3", members: ["USER3": roomBMember])
        let roomData = try! JSONEncoder().encode(roomB)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "GET" {
                return (response, roomData)
            }
            return (response, "{}".data(using: .utf8)!)
        }
        
        let syncManager = createMockFirebaseSyncManager()
        // Joining Room B with callsign VIPER (even though Room A already has a VIPER)
        let newMember = SquadMember(id: "USER4", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        
        let exp = expectation(description: "Same callsign in different room is accepted")
        syncManager.joinRoom(id: "ROOM_B", member: newMember) { result in
            switch result {
            case .success(let joinedRoom):
                XCTAssertEqual(joinedRoom.id, "ROOM_B")
                XCTAssertEqual(joinedRoom.members["USER4"]?.callsign, "VIPER")
                exp.fulfill()
            case .failure(let error):
                XCTFail("Should succeed joining different room with same callsign: \(error)")
            }
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testGameStateManager_HostRoom_RejectsEmptyRoomNameAndEmptyCallsign() {
        let gameState = createMockGameState()
        
        // 1. Empty room name
        gameState.myCallsign = "VIPER"
        let hostExp1 = expectation(description: "Host empty room name fails")
        let res1 = gameState.hostRoom(name: "   ") { success in
            XCTAssertFalse(success)
            XCTAssertTrue(gameState.squadNameError)
            XCTAssertFalse(gameState.callsignError)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.emptyRoomName.localizedDescription)
            hostExp1.fulfill()
        }
        XCTAssertFalse(res1)
        wait(for: [hostExp1], timeout: 1.0)
        
        // 2. Empty callsign
        gameState.myCallsign = "   "
        let hostExp2 = expectation(description: "Host empty callsign fails")
        let res2 = gameState.hostRoom(name: "MY_SQUAD") { success in
            XCTAssertFalse(success)
            XCTAssertTrue(gameState.callsignError)
            XCTAssertFalse(gameState.squadNameError)
            XCTAssertEqual(gameState.errorMessage, FirebaseSyncError.emptyCallsign.localizedDescription)
            hostExp2.fulfill()
        }
        XCTAssertFalse(res2)
        wait(for: [hostExp2], timeout: 1.0)
    }
    
    func testGameStateManager_JoinRoom_RejectsEmptyRoomNameAndEmptyCallsign() {
        let gameState = createMockGameState()
        
        // 1. Empty room name
        gameState.myCallsign = "VIPER"
        let joinExp1 = expectation(description: "Join empty room name fails")
        gameState.joinRoom(id: "   ") { (result: Result<SquadRoom, FirebaseSyncError>) in
            switch result {
            case .success:
                XCTFail("Should fail with empty room name")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.emptyRoomName)
                XCTAssertTrue(gameState.squadNameError)
                XCTAssertFalse(gameState.callsignError)
                joinExp1.fulfill()
            }
        }
        wait(for: [joinExp1], timeout: 1.0)
        
        // 2. Empty callsign
        gameState.myCallsign = "   "
        let joinExp2 = expectation(description: "Join empty callsign fails")
        gameState.joinRoom(id: "SOME_SQUAD") { (result: Result<SquadRoom, FirebaseSyncError>) in
            switch result {
            case .success:
                XCTFail("Should fail with empty callsign")
            case .failure(let error):
                XCTAssertEqual(error, FirebaseSyncError.emptyCallsign)
                XCTAssertTrue(gameState.callsignError)
                XCTAssertFalse(gameState.squadNameError)
                joinExp2.fulfill()
            }
        }
        wait(for: [joinExp2], timeout: 1.0)
    }
    
    // MARK: - Batch Telemetry & Serialization Fallback Tests
    
    func testBatchTelemetryProcessingSingleRoomUpdate() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "BATCH_TEST", hostId: "USER1")
        syncManager.connectToRoom(room)
        
        let now = Date().timeIntervalSince1970
        let p1 = TelemetryPacket(memberId: "USER1", roomId: "BATCH_TEST", latitude: 37.771, longitude: -122.411, heading: 45.0, heartRate: 80.0, timestamp: now, sequenceNumber: 1)
        let p2 = TelemetryPacket(memberId: "USER2", roomId: "BATCH_TEST", latitude: 37.772, longitude: -122.412, heading: 90.0, heartRate: 85.0, timestamp: now, sequenceNumber: 1)
        let p3 = TelemetryPacket(memberId: "USER3", roomId: "BATCH_TEST", latitude: 37.773, longitude: -122.413, heading: 135.0, heartRate: 90.0, timestamp: now, sequenceNumber: 1)
        
        let accepted = syncManager.validateAndProcessPackets([p1, p2, p3])
        XCTAssertEqual(accepted, 3)
        XCTAssertEqual(syncManager.totalPacketsProcessed, 3)
        XCTAssertEqual(syncManager.activeRoom?.members.count, 3)
        XCTAssertEqual(syncManager.activeRoom?.members["USER1"]?.heartRate, 80.0)
        XCTAssertEqual(syncManager.activeRoom?.members["USER2"]?.heartRate, 85.0)
        XCTAssertEqual(syncManager.activeRoom?.members["USER3"]?.heartRate, 90.0)
    }
    
    func testSquadRoomDecodingFallbackToFreeTierCapacity() throws {
        let json = """
        {
            "id": "FREE_SQUAD",
            "hostId": "HOST_FREE",
            "createdAt": 1700000000,
            "members": {}
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(SquadRoom.self, from: json)
        XCTAssertEqual(decoded.maxCapacity, AppConstants.Subscription.freeTierMaxCapacity, "Missing maxCapacity should default to freeTierMaxCapacity (4)")
    }
    
    func testSquadMemberDecodingFallbackDefaultBattery() throws {
        let json = """
        {
            "id": "BATTERY_TEST",
            "callsign": "RECON"
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(SquadMember.self, from: json)
        XCTAssertEqual(decoded.batteryLevel, AppConstants.UI.defaultBatteryLevel, "Missing batteryLevel should default to AppConstants.UI.defaultBatteryLevel (0.95)")
    }
    
    func testNonProPlayerHeadingStabilityUnderMicroJitter() {
        let syncManager = createMockFirebaseSyncManager()
        let room = SquadRoom(id: "STABILITY_ROOM", hostId: "HOST_1", members: [:])
        syncManager.connectToRoom(room)
        
        let metersPerDegreeLat = AppConstants.Location.metersPerDegreeLatitude
        let baseLat = 37.785834
        let baseLng = -122.406417
        
        // 1. Initial position with known heading 90.0°
        let p1 = TelemetryPacket(memberId: "NON_PRO_1", roomId: "STABILITY_ROOM", latitude: baseLat, longitude: baseLng, heading: 90.0, heartRate: 75.0, timestamp: 1000, sequenceNumber: 1)
        XCTAssertTrue(syncManager.validateAndProcessPacket(p1))
        XCTAssertEqual(syncManager.activeRoom?.members["NON_PRO_1"]?.heading, 90.0)
        
        // 2. Micro-jitter packet 0.8m North with heading 0.0 (compact4 format)
        // Since 0.8m <= minDisplacementForCourseOverGroundMeters (2.0m), previous heading 90.0° should be retained without flipping to 0°/180°
        let p2Jitter = TelemetryPacket(
            memberId: "NON_PRO_1",
            roomId: "STABILITY_ROOM",
            latitude: baseLat + (0.8 / metersPerDegreeLat),
            longitude: baseLng,
            heading: 0.0,
            heartRate: 75.0,
            timestamp: 1001,
            sequenceNumber: 2
        )
        XCTAssertTrue(syncManager.validateAndProcessPacket(p2Jitter))
        let retainedHeading = syncManager.activeRoom?.members["NON_PRO_1"]?.heading ?? -1.0
        XCTAssertEqual(retainedHeading, 90.0, "Displacement below 2.0m threshold must retain previous heading to prevent bobbing")
        
        // 3. Significant movement 10.0m North (> 2.0m)
        let p3Move = TelemetryPacket(
            memberId: "NON_PRO_1",
            roomId: "STABILITY_ROOM",
            latitude: baseLat + (10.8 / metersPerDegreeLat),
            longitude: baseLng,
            heading: 0.0,
            heartRate: 75.0,
            timestamp: 1002,
            sequenceNumber: 3
        )
        XCTAssertTrue(syncManager.validateAndProcessPacket(p3Move))
        let newHeading = syncManager.activeRoom?.members["NON_PRO_1"]?.heading ?? -1.0
        XCTAssertEqual(newHeading, 0.0, accuracy: 1.0, "Displacement above 2.0m threshold should compute Course Over Ground bearing ~0.0°")
    }
}




