import Foundation
import Combine
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Payloads for room actions passed over WatchConnectivity
public struct WCRoomAction {
    public let actionType: String
    public let roomName: String
    public let pin: String?
    public let isHosting: Bool
    
    public init(actionType: String, roomName: String, pin: String?, isHosting: Bool) {
        self.actionType = actionType
        self.roomName = roomName
        self.pin = pin
        self.isHosting = isHosting
    }
}

/// Payload for configuration values passed over WatchConnectivity
public struct WCConfigPayload {
    public let callsign: String?
    public let roomName: String?
    public let pin: String?
    public let theme: String?
    
    public init(callsign: String? = nil, roomName: String? = nil, pin: String? = nil, theme: String? = nil) {
        self.callsign = callsign
        self.roomName = roomName
        self.pin = pin
        self.theme = theme
    }
}

public final class WatchConnectivityManager: NSObject, ObservableObject {
    public static let shared = WatchConnectivityManager()
    
    @Published public var isSessionSupported: Bool = false
    @Published public var isReachable: Bool = false
    @Published public var isPaired: Bool = false
    @Published public var isWatchAppInstalled: Bool = false
    
    // Callbacks to GameStateManager
    public var onConfigReceived: ((WCConfigPayload) -> Void)?
    public var onRoomActionReceived: ((WCRoomAction) -> Void)?
    public var onIdentityReceived: ((String) -> Void)?
    
    public override init() {
        super.init()
        #if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            self.isSessionSupported = true
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        #endif
    }
    
    public func activate() {
        #if canImport(WatchConnectivity)
        if WCSession.isSupported() && WCSession.default.activationState == .notActivated {
            WCSession.default.activate()
        }
        #endif
    }
    
    // MARK: - Outgoing Transmissions
    
    /// Sends real-time config updates (typing / settings change).
    /// Uses real-time `sendMessage` if reachable, alongside `updateApplicationContext` for offline persistence.
    public func sendConfigUpdate(callsign: String? = nil, roomName: String? = nil, pin: String? = nil, theme: String? = nil) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        
        var dict: [String: Any] = [
            AppConstants.WatchConnectivity.messageTypeKey: AppConstants.WatchConnectivity.MessageType.configSync,
            AppConstants.WatchConnectivity.timestampKey: Date().timeIntervalSince1970
        ]
        
        if let callsign = callsign { dict[AppConstants.WatchConnectivity.callsignKey] = callsign }
        if let roomName = roomName { dict[AppConstants.WatchConnectivity.roomNameKey] = roomName }
        if let pin = pin { dict[AppConstants.WatchConnectivity.pinKey] = pin }
        if let theme = theme { dict[AppConstants.WatchConnectivity.themeKey] = theme }
        
        // 1. Send live message if reachable
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { error in
                print("[WatchConnectivity] Live config sendMessage error: \(error.localizedDescription)")
            }
        }
        
        // 2. Guaranteed background delivery via application context
        do {
            try session.updateApplicationContext(dict)
        } catch {
            print("[WatchConnectivity] updateApplicationContext error: \(error.localizedDescription)")
        }
        #endif
    }
    
    /// Sends room actions (Host, Join, Leave, Disband).
    public func sendRoomAction(actionType: String, roomName: String, pin: String? = nil, isHosting: Bool = false) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        
        var dict: [String: Any] = [
            AppConstants.WatchConnectivity.messageTypeKey: AppConstants.WatchConnectivity.MessageType.roomAction,
            AppConstants.WatchConnectivity.actionTypeKey: actionType,
            AppConstants.WatchConnectivity.roomNameKey: roomName,
            AppConstants.WatchConnectivity.isHostingKey: isHosting,
            AppConstants.WatchConnectivity.timestampKey: Date().timeIntervalSince1970
        ]
        if let pin = pin { dict[AppConstants.WatchConnectivity.pinKey] = pin }
        
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { error in
                print("[WatchConnectivity] Live action sendMessage error: \(error.localizedDescription)")
            }
        }
        
        // Also queue via transferUserInfo to guarantee delivery if connection drops
        session.transferUserInfo(dict)
        #endif
    }
    
    /// Synchronizes the single player identity memberId.
    public func sendIdentityHandshake(memberId: String) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        
        let dict: [String: Any] = [
            AppConstants.WatchConnectivity.messageTypeKey: AppConstants.WatchConnectivity.MessageType.identityHandshake,
            AppConstants.WatchConnectivity.memberIdKey: memberId,
            AppConstants.WatchConnectivity.timestampKey: Date().timeIntervalSince1970
        ]
        
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        }
        
        session.transferUserInfo(dict)
        #endif
    }
    
    // MARK: - Incoming Message Parsing
    
    private func handleIncomingPayload(_ dict: [String: Any]) {
        guard let msgType = dict[AppConstants.WatchConnectivity.messageTypeKey] as? String else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch msgType {
            case AppConstants.WatchConnectivity.MessageType.configSync:
                let payload = WCConfigPayload(
                    callsign: dict[AppConstants.WatchConnectivity.callsignKey] as? String,
                    roomName: dict[AppConstants.WatchConnectivity.roomNameKey] as? String,
                    pin: dict[AppConstants.WatchConnectivity.pinKey] as? String,
                    theme: dict[AppConstants.WatchConnectivity.themeKey] as? String
                )
                self.onConfigReceived?(payload)
                
            case AppConstants.WatchConnectivity.MessageType.roomAction:
                if let action = dict[AppConstants.WatchConnectivity.actionTypeKey] as? String,
                   let roomName = dict[AppConstants.WatchConnectivity.roomNameKey] as? String {
                    let pin = dict[AppConstants.WatchConnectivity.pinKey] as? String
                    let isHosting = dict[AppConstants.WatchConnectivity.isHostingKey] as? Bool ?? false
                    let actionPayload = WCRoomAction(
                        actionType: action,
                        roomName: roomName,
                        pin: pin,
                        isHosting: isHosting
                    )
                    self.onRoomActionReceived?(actionPayload)
                }
                
            case AppConstants.WatchConnectivity.MessageType.identityHandshake:
                if let memberId = dict[AppConstants.WatchConnectivity.memberIdKey] as? String {
                    self.onIdentityReceived?(memberId)
                }
                
            default:
                break
            }
        }
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityManager: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif
        }
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) { }
    
    public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate session if user switches watches
        WCSession.default.activate()
    }
    
    public func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
    #endif
    
    // 1. Live interactive messages
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncomingPayload(message)
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        handleIncomingPayload(message)
        replyHandler(["status": "acknowledged"])
    }
    
    // 2. Application Context updates
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleIncomingPayload(applicationContext)
    }
    
    // 3. User Info transfers
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleIncomingPayload(userInfo)
    }
}
#endif
