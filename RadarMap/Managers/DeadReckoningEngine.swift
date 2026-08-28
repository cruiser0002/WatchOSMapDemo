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
        public var coordinateStartTime: TimeInterval
        public var coordinateDuration: TimeInterval
        public var startHeading: Double
        public var targetHeading: Double
        public var headingStartTime: TimeInterval
        public var headingDuration: TimeInterval
        public var lastUpdate: TimeInterval
        
        public var startTime: TimeInterval {
            get { coordinateStartTime }
            set { coordinateStartTime = newValue }
        }
        public var duration: TimeInterval {
            get { coordinateDuration }
            set { coordinateDuration = newValue }
        }
        
        public init(
            coordinate: CLLocationCoordinate2D,
            heading: Double,
            startCoordinate: CLLocationCoordinate2D,
            targetCoordinate: CLLocationCoordinate2D,
            startHeading: Double,
            targetHeading: Double,
            startTime: TimeInterval,
            duration: TimeInterval,
            lastUpdate: TimeInterval,
            headingStartTime: TimeInterval? = nil,
            headingDuration: TimeInterval? = nil
        ) {
            self.coordinate = coordinate
            self.heading = heading
            self.startCoordinate = startCoordinate
            self.targetCoordinate = targetCoordinate
            self.coordinateStartTime = startTime
            self.coordinateDuration = duration
            self.startHeading = startHeading
            self.targetHeading = targetHeading
            self.headingStartTime = headingStartTime ?? startTime
            self.headingDuration = headingDuration ?? duration
            self.lastUpdate = lastUpdate
        }
    }
    
    @Published public private(set) var smoothedMembers: [String: SmoothState] = [:]
    @Published public private(set) var localPlayerState: SmoothState?
    
    private var displayTimer: AnyCancellable?
    
    public init() {
        startInterpolationLoop()
    }
    
    public func startInterpolationLoop() {
        guard displayTimer == nil else { return }
        // Run smooth 20Hz tick for dead-reckoning smoothing (local & remote)
        displayTimer = Timer.publish(every: AppConstants.Timing.DisplayRefresh.radarUIIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateInterpolation()
            }
    }
    
    public func stopInterpolationLoop() {
        displayTimer?.cancel()
        displayTimer = nil
    }
    
    /// Updates the local player ("ME") coordinate and heading with smooth gliding interpolation
    public func updateLocalPlayer(coordinate: CLLocationCoordinate2D, heading: Double) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateLocalPlayer(coordinate: coordinate, heading: heading)
            }
            return
        }
        
        let now = Date().timeIntervalSince1970
        
        if var current = localPlayerState {
            let elapsedSinceLast = max(0.5, min(2.5, now - current.lastUpdate))
            current.startCoordinate = current.coordinate
            current.targetCoordinate = coordinate
            current.coordinateStartTime = now
            current.coordinateDuration = elapsedSinceLast
            current.startHeading = current.heading
            current.targetHeading = heading
            current.headingStartTime = now
            current.headingDuration = min(0.3, elapsedSinceLast)
            current.lastUpdate = now
            localPlayerState = current
        } else {
            localPlayerState = SmoothState(
                coordinate: coordinate,
                heading: heading,
                startCoordinate: coordinate,
                targetCoordinate: coordinate,
                startHeading: heading,
                targetHeading: heading,
                startTime: now,
                duration: 1.0,
                lastUpdate: now
            )
        }
        
        startInterpolationLoop()
    }
    
    /// Updates only the local player's heading for high-frequency compass responsiveness
    public func updateLocalPlayerHeading(_ heading: Double) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateLocalPlayerHeading(heading)
            }
            return
        }
        
        let now = Date().timeIntervalSince1970
        if var current = localPlayerState {
            current.startHeading = current.heading
            current.targetHeading = heading
            // Quick 0.15s heading smoothing to eliminate compass jitter without disturbing coordinate gliding
            current.headingStartTime = now
            current.headingDuration = 0.15
            current.lastUpdate = now
            localPlayerState = current
            startInterpolationLoop()
        }
    }
    
    /// Retrieves the smoothed coordinate for the local player
    public func smoothedLocalCoordinate(fallback: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        return localPlayerState?.coordinate ?? fallback
    }
    
    /// Retrieves the smoothed heading for the local player
    public func smoothedLocalHeading(fallback: Double) -> Double {
        return localPlayerState?.heading ?? fallback
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
            current.coordinateStartTime = now
            current.coordinateDuration = elapsedSinceLast
            current.startHeading = current.heading
            current.targetHeading = newHeading
            current.headingStartTime = now
            current.headingDuration = elapsedSinceLast
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
        if smoothedMembers.isEmpty && localPlayerState == nil {
            stopInterpolationLoop()
        }
    }
    
    public func clearRemoteMembers() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.clearRemoteMembers()
            }
            return
        }
        smoothedMembers.removeAll()
        if smoothedMembers.isEmpty && localPlayerState == nil {
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
        localPlayerState = nil
        stopInterpolationLoop()
    }
    
    private func updateInterpolation() {
        let now = Date().timeIntervalSince1970
        var hasChanges = false
        var anyActive = false
        
        // 1. Interpolate Local Player ("ME")
        if let local = localPlayerState {
            let coordElapsed = now - local.coordinateStartTime
            let coordProgress = min(1.0, max(0.0, coordElapsed / max(0.05, local.coordinateDuration)))
            
            let hdgElapsed = now - local.headingStartTime
            let hdgProgress = min(1.0, max(0.0, hdgElapsed / max(0.05, local.headingDuration)))
            
            var newCoord = local.coordinate
            var newHdg = local.heading
            
            if coordProgress < 1.0 {
                anyActive = true
                // Linear constant velocity interpolation for smooth continuous movement without start/stop pulsation
                let lat = local.startCoordinate.latitude + (local.targetCoordinate.latitude - local.startCoordinate.latitude) * coordProgress
                let lon = local.startCoordinate.longitude + (local.targetCoordinate.longitude - local.startCoordinate.longitude) * coordProgress
                newCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if local.coordinate != local.targetCoordinate {
                newCoord = local.targetCoordinate
            }
            
            if hdgProgress < 1.0 {
                anyActive = true
                // 2D Unit vector circular interpolation for smooth turning
                newHdg = LocationHeadingManager.circularInterpolate(from: local.startHeading, to: local.targetHeading, weight: hdgProgress)
            } else if local.heading != local.targetHeading {
                newHdg = local.targetHeading
            }
            
            if abs(local.coordinate.latitude - newCoord.latitude) > 1e-8 || abs(local.coordinate.longitude - newCoord.longitude) > 1e-8 || abs(local.heading - newHdg) > 0.05 {
                localPlayerState?.coordinate = newCoord
                localPlayerState?.heading = newHdg
                hasChanges = true
            }
        }
        
        // 2. Interpolate Remote Teammates
        for (id, state) in smoothedMembers {
            let coordElapsed = now - state.coordinateStartTime
            let coordProgress = min(1.0, max(0.0, coordElapsed / max(0.05, state.coordinateDuration)))
            
            let hdgElapsed = now - state.headingStartTime
            let hdgProgress = min(1.0, max(0.0, hdgElapsed / max(0.05, state.headingDuration)))
            
            var newCoord = state.coordinate
            var newHdg = state.heading
            
            if coordProgress < 1.0 {
                anyActive = true
                // Linear constant velocity interpolation for smooth continuous movement without start/stop pulsation
                let lat = state.startCoordinate.latitude + (state.targetCoordinate.latitude - state.startCoordinate.latitude) * coordProgress
                let lon = state.startCoordinate.longitude + (state.targetCoordinate.longitude - state.startCoordinate.longitude) * coordProgress
                newCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if state.coordinate != state.targetCoordinate {
                newCoord = state.targetCoordinate
            }
            
            if hdgProgress < 1.0 {
                anyActive = true
                // 2D Unit vector circular interpolation for smooth turning
                newHdg = LocationHeadingManager.circularInterpolate(from: state.startHeading, to: state.targetHeading, weight: hdgProgress)
            } else if state.heading != state.targetHeading {
                newHdg = state.targetHeading
            }
            
            if abs(state.coordinate.latitude - newCoord.latitude) > 1e-7 || abs(state.coordinate.longitude - newCoord.longitude) > 1e-7 || abs(state.heading - newHdg) > 0.1 {
                smoothedMembers[id]?.coordinate = newCoord
                smoothedMembers[id]?.heading = newHdg
                hasChanges = true
            }
        }
        
        if hasChanges {
            objectWillChange.send()
        }
        
        // Automatic Idle Sleep: If all players have reached their target endpoints, sleep timer until next packet / GPS fix
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
    /// Uses a single dictionary lookup (instead of two) to minimise overhead inside the render loop.
    public func smoothedMember(for member: SquadMember) -> SquadMember {
        let state = smoothedMembers[member.id]
        let coord = state?.coordinate ?? member.coordinate
        let hdg   = state?.heading   ?? member.heading
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
