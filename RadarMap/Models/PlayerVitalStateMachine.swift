import Foundation

/// Represents the deterministic vital status and health telemetry state of the player.
public enum PlayerVitalState: Equatable, Codable {
    case active(heartRate: Double)
    case downed
    
    public var isDead: Bool {
        if case .downed = self { return true }
        return false
    }
    
    public var effectiveHeartRate: Double {
        switch self {
        case let .active(hr):
            return hr > 0 ? hr : AppConstants.Health.defaultRestingHeartRate
        case .downed:
            return AppConstants.Health.flatlineHeartRate
        }
    }
    
    public var status: MemberStatus {
        isDead ? .downed : .active
    }
}

/// Inputs/Actions that advance the PlayerVitalStateMachine.
public enum PlayerVitalAction: Equatable {
    case setKIA(Bool)
    case updateHeartRate(Double)
    case toggleKIA
}

/// Dedicated, deterministic State Machine governing player life/death state and biometrics.
public struct PlayerVitalStateMachine: Equatable {
    public private(set) var state: PlayerVitalState
    
    public init(initialState: PlayerVitalState = AppConstants.Health.defaultIsDead ? .downed : .active(heartRate: AppConstants.Health.defaultRestingHeartRate)) {
        self.state = initialState
    }
    
    /// Pure state transition function that advances the player vital state machine based on inputs.
    @discardableResult
    public mutating func handle(_ action: PlayerVitalAction) -> PlayerVitalStateMachine {
        switch action {
        case let .setKIA(isKia):
            if isKia {
                state = .downed
            } else {
                state = .active(heartRate: AppConstants.Health.defaultRestingHeartRate)
            }
            
        case let .updateHeartRate(hr):
            switch state {
            case .active:
                state = .active(heartRate: hr)
            case .downed:
                // Downed flatlines override incoming sensor heart rate
                break
            }
            
        case .toggleKIA:
            if state.isDead {
                state = .active(heartRate: AppConstants.Health.defaultRestingHeartRate)
            } else {
                state = .downed
            }
        }
        return self
    }
}
