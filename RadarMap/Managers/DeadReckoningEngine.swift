import Foundation
import CoreLocation
import Combine
import SwiftUI

/// Dead Reckoning and Smooth Interpolation Engine for Remote Players
public final class DeadReckoningEngine: ObservableObject {
    public static let shared = DeadReckoningEngine()
    
    public struct SmoothState {
        public var coordinate: CLLocationCoordinate2D
        public var heading: Double
        public var startCoordinate: CLLocationCoordinate2D
        public var targetCoordinate: CLLocationCoordinate2D
        public var startHeading: Double
        public var targetHeading: Double
        public var startTime: TimeInterval
        public var duration: TimeInterval
        public var lastUpdate: TimeInterval
    }
    
    @Published public private(set) var smoothedMembers: [String: SmoothState] = [:]
    
    private var displayTimer: AnyCancellable?
    
    public init() {
        startInterpolationLoop()
    }
    
    public func startInterpolationLoop() {
        guard displayTimer == nil else { return }
        // Run energy-efficient 5Hz tick for teammate dead-reckoning smoothing
        displayTimer = Timer.publish(every: AppConstants.Timing.DisplayRefresh.teammateDeadReckoningIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateInterpolation()
            }
    }
    
    public func stopInterpolationLoop() {
        displayTimer?.cancel()
        displayTimer = nil
    }
    
    /// Called whenever a new telemetry packet is received for a remote player
    public func updateRemotePlayer(id: String, newCoordinate: CLLocationCoordinate2D, newHeading: Double, packetTimestamp: TimeInterval) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateRemotePlayer(id: id, newCoordinate: newCoordinate, newHeading: newHeading, packetTimestamp: packetTimestamp)
            }
            return
        }
        
        let now = Date().timeIntervalSince1970
        
        if var current = smoothedMembers[id] {
            let elapsedSinceLast = max(0.5, min(3.0, now - current.lastUpdate))
            current.startCoordinate = current.coordinate
            current.targetCoordinate = newCoordinate
            current.startHeading = current.heading
            current.targetHeading = newHeading
            current.startTime = now
            current.duration = elapsedSinceLast
            current.lastUpdate = now
            smoothedMembers[id] = current
        } else {
            smoothedMembers[id] = SmoothState(
                coordinate: newCoordinate,
                heading: newHeading,
                startCoordinate: newCoordinate,
                targetCoordinate: newCoordinate,
                startHeading: newHeading,
                targetHeading: newHeading,
                startTime: now,
                duration: 1.0,
                lastUpdate: now
            )
        }
        
        // Wake interpolation loop if it was asleep
        startInterpolationLoop()
    }
    
    public func removePlayer(id: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.removePlayer(id: id)
            }
            return
        }
        smoothedMembers.removeValue(forKey: id)
        if smoothedMembers.isEmpty {
            stopInterpolationLoop()
        }
    }
    
    public func clearAll() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.clearAll()
            }
            return
        }
        smoothedMembers.removeAll()
        stopInterpolationLoop()
    }
    
    private func updateInterpolation() {
        guard !smoothedMembers.isEmpty else {
            stopInterpolationLoop()
            return
        }
        let now = Date().timeIntervalSince1970
        var hasChanges = false
        var anyActive = false
        
        for (id, state) in smoothedMembers {
            let elapsed = now - state.startTime
            let progress = min(1.0, max(0.0, elapsed / max(0.1, state.duration)))
            
            if progress < 1.0 {
                anyActive = true
            }
            
            // Hermite SmoothStep interpolation for coordinate gliding
            let smoothProgress = progress * progress * (3.0 - 2.0 * progress)
            
            let lat = state.startCoordinate.latitude + (state.targetCoordinate.latitude - state.startCoordinate.latitude) * smoothProgress
            let lon = state.startCoordinate.longitude + (state.targetCoordinate.longitude - state.startCoordinate.longitude) * smoothProgress
            
            // 2D Unit vector circular interpolation for smooth turning
            let smoothHdg = LocationHeadingManager.circularInterpolate(from: state.startHeading, to: state.targetHeading, weight: smoothProgress)
            
            if abs(state.coordinate.latitude - lat) > 1e-7 || abs(state.coordinate.longitude - lon) > 1e-7 || abs(state.heading - smoothHdg) > 0.1 {
                smoothedMembers[id]?.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                smoothedMembers[id]?.heading = smoothHdg
                hasChanges = true
            }
        }
        
        if hasChanges {
            objectWillChange.send()
        }
        
        // Automatic Idle Sleep: If all players have reached their target endpoints, sleep timer until next packet
        if !anyActive {
            stopInterpolationLoop()
        }
    }
    
    /// Retrieves the smoothed coordinate for a remote member (falling back to member coordinate if not yet tracked)
    public func coordinate(for member: SquadMember) -> CLLocationCoordinate2D {
        return smoothedMembers[member.id]?.coordinate ?? member.coordinate
    }
    
    /// Retrieves the smoothed heading for a remote member (falling back to member heading if not yet tracked)
    public func heading(for member: SquadMember) -> Double {
        return smoothedMembers[member.id]?.heading ?? member.heading
    }
    
    /// Returns a copy of the given member updated with smoothed dead-reckoned coordinate and heading.
    public func smoothedMember(for member: SquadMember) -> SquadMember {
        let coord = coordinate(for: member)
        let hdg = heading(for: member)
        return SquadMember(
            id: member.id,
            callsign: member.callsign,
            latitude: coord.latitude,
            longitude: coord.longitude,
            altitude: member.altitude,
            heading: hdg,
            heartRate: member.heartRate,
            batteryLevel: member.batteryLevel,
            lastUpdatedTimestamp: member.lastUpdatedTimestamp,
            sequenceNumber: member.sequenceNumber,
            status: member.status,
            isHost: member.isHost
        )
    }
}
