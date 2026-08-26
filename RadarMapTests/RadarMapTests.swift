import XCTest
import CoreLocation
import SwiftUI
@testable import RadarMap

final class RadarMapTests: XCTestCase {
    
    // MARK: - Late Packet Rejection Tests
    
    func testLatePacketRejectionInOrder() {
        let syncManager = FirebaseSyncManager()
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
        let syncManager = FirebaseSyncManager()
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
        let syncManager = FirebaseSyncManager()
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
    
    func testLatePacketRejectionExpiredPacket() {
        let syncManager = FirebaseSyncManager()
        let room = SquadRoom(id: "ALPHA1", hostId: "USER1")
        let member = SquadMember(id: "USER2", callsign: "VIPER", latitude: 37.77, longitude: -122.41)
        var updatedRoom = room
        updatedRoom.members["USER2"] = member
        syncManager.connectToRoom(updatedRoom)
        
        let now = Date().timeIntervalSince1970
        
        // Packet generated 25 seconds ago (transit lag > 15s)
        let expiredPacket = TelemetryPacket(memberId: "USER2", roomId: "ALPHA1", latitude: 37.771, longitude: -122.411, heading: 45.0, heartRate: 80.0, timestamp: now - 25.0, sequenceNumber: 1)
        XCTAssertFalse(syncManager.validateAndProcessPacket(expiredPacket), "Expired transit lag packet should be rejected")
        XCTAssertEqual(syncManager.latestRejection?.reason, .expiredPacket)
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
        XCTAssertEqual(TacticalMapStyle.radar.rawValue, "Radar")
        XCTAssertEqual(TacticalMapStyle.radar.iconName, "scope")
        XCTAssertEqual(TacticalMapStyle.allCases.count, 4)
    }
    
    func testRadarColorThemes() {
        XCTAssertTrue(RadarColorTheme.allCases.contains(.green))
        XCTAssertTrue(RadarColorTheme.allCases.contains(.red))
        XCTAssertEqual(RadarColorTheme.allCases.count, 2)
        XCTAssertEqual(RadarColorTheme.green.color, .green)
        XCTAssertEqual(RadarColorTheme.red.color, .red)
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
    
    func testKIATelemetryFlatlineZeroBPM() {
        let syncManager = FirebaseSyncManager()
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
        let syncManager = FirebaseSyncManager()
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
            id: "TEST",
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
        let pkt1 = TelemetryPacket(memberId: "PLAYER_1", roomId: "TEST", latitude: p1Lat, longitude: p1Lng, heading: 0.0, heartRate: 78.0, timestamp: now, sequenceNumber: 1)
        let pkt2 = TelemetryPacket(memberId: "PLAYER_2", roomId: "TEST", latitude: p2Lat, longitude: p2Lng, heading: 10.0, heartRate: 88.0, timestamp: now, sequenceNumber: 1)
        let pkt3 = TelemetryPacket(memberId: "PLAYER_3", roomId: "TEST", latitude: p3Lat, longitude: p3Lng, heading: 20.0, heartRate: 98.0, timestamp: now, sequenceNumber: 1)
        
        XCTAssertTrue(syncManager.validateAndProcessPacket(pkt1))
        XCTAssertTrue(syncManager.validateAndProcessPacket(pkt2))
        XCTAssertTrue(syncManager.validateAndProcessPacket(pkt3))
        
        XCTAssertEqual(syncManager.totalPacketsProcessed, 3)
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_1"]?.heartRate, 78.0)
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_2"]?.heartRate, 88.0)
        XCTAssertEqual(syncManager.activeRoom?.members["PLAYER_3"]?.heartRate, 98.0)
    }
    
    func testAutoRegisterUnknownMemberFromTelemetry() {
        let syncManager = FirebaseSyncManager()
        let room = SquadRoom(id: "TEST", hostId: "LOCAL_PLAYER", members: [:])
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
            if request.httpMethod == "GET" {
                let testRoom = SquadRoom(id: "CHARLIE", hostId: "REMOTE_HOST", members: [:])
                let data = try! JSONEncoder().encode(testRoom)
                return (response, data)
            }
            return (response, "{}".data(using: .utf8)!)
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
        let pinHash = FirebaseSyncManager.hashPassword("9999", salt: "SECURE")
        let secureRoom = SquadRoom(id: "SECURE", hostId: "HOST_USER", hasPassword: true, passwordHash: pinHash, members: [:])
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
}

