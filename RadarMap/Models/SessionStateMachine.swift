import Foundation

/// Represents the deterministic lifecycle state of a tactical multiplayer session.
public enum SessionState: Equatable {
    case disconnected
    case initiatingHost(roomName: String, pin: String?)
    case hosting(room: SquadRoom)
    case initiatingJoin(roomId: String, pin: String?)
    case joined(room: SquadRoom)
    case error(message: String)
    
    public var isHosting: Bool {
        if case .hosting = self { return true }
        return false
    }
    
    public var isInitiatingHost: Bool {
        if case .initiatingHost = self { return true }
        return false
    }
    
    public var isJoining: Bool {
        if case .initiatingJoin = self { return true }
        return false
    }
    
    public var isActiveSession: Bool {
        switch self {
        case .hosting, .joined:
            return true
        default:
            return false
        }
    }
    
    public var activeRoom: SquadRoom? {
        switch self {
        case let .hosting(room):
            return room
        case let .joined(room):
            return room
        default:
            return nil
        }
    }
    
    public var errorMessage: String? {
        if case let .error(msg) = self {
            return msg
        }
        return nil
    }
}

/// Inputs/Actions that advance the SessionStateMachine.
public enum SessionAction: Equatable {
    case startHost(name: String, pin: String?)
    case hostSuccess(room: SquadRoom)
    case hostFailure(error: String)
    case startJoin(id: String, pin: String?)
    case joinSuccess(room: SquadRoom)
    case joinFailure(error: String)
    case updateRoom(room: SquadRoom)
    case leave
    case disband
    case clearError
}

/// Dedicated, deterministic State Machine governing Tactical Session connections and rooms.
public struct SessionStateMachine: Equatable {
    public private(set) var state: SessionState
    
    public init(initialState: SessionState = .disconnected) {
        self.state = initialState
    }
    
    /// Pure state transition function that advances the session state machine based on inputs.
    @discardableResult
    public mutating func handle(_ action: SessionAction) -> SessionStateMachine {
        switch action {
        case let .startHost(name, pin):
            state = .initiatingHost(roomName: name, pin: pin)
            
        case let .hostSuccess(room):
            state = .hosting(room: room)
            
        case let .hostFailure(error):
            state = .error(message: error)
            
        case let .startJoin(id, pin):
            state = .initiatingJoin(roomId: id, pin: pin)
            
        case let .joinSuccess(room):
            state = .joined(room: room)
            
        case let .joinFailure(error):
            state = .error(message: error)
            
        case let .updateRoom(room):
            switch state {
            case .hosting:
                state = .hosting(room: room)
            case .joined:
                state = .joined(room: room)
            default:
                break
            }
            
        case .leave, .disband:
            state = .disconnected
            
        case .clearError:
            if case .error = state {
                state = .disconnected
            }
        }
        return self
    }
}
