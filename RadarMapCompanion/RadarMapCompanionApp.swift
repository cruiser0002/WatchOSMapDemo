import SwiftUI

@main
struct RadarMapCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            iOSCompanionContentView()
        }
    }
}

// MARK: - Tactical Guide Callout Model
enum TacticalHUDCallout: String, CaseIterable, Identifiable {
    case config = "Configuration"
    case tacticalCommands = "Tactical Commands"
    case centerMap = "Center Map"
    case mapView = "Map View"
    case heartRate = "Heart Rate & KIA"
    
    var id: String { rawValue }
    
    var codeTag: String {
        switch self {
        case .config: return "SYS-CFG"
        case .tacticalCommands: return "TAC-COM"
        case .centerMap: return "NAV-POS"
        case .mapView: return "HUD-MODE"
        case .heartRate: return "BIO-STAT"
        }
    }
    
    var iconName: String {
        switch self {
        case .config: return "gearshape.fill"
        case .tacticalCommands: return "star.fill"
        case .centerMap: return "location.fill"
        case .mapView: return "scope"
        case .heartRate: return "waveform.path.ecg"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .config: return "Settings"
        case .tacticalCommands: return "Commands"
        case .centerMap: return "Center Map"
        case .mapView: return "Map View"
        case .heartRate: return "Pulse & KIA"
        }
    }
    
    var actionInstruction: String {
        switch self {
        case .config:
            return "Tap the top-left gear icon to open squad management, change radar color themes, adjust refresh rates, and configure audio/haptics."
        case .tacticalCommands:
            return "Tap the top center 3-star badge to place tactical objective markers, rally points, enemy warnings, and broadcast squad orders."
        case .centerMap:
            return "Tap the bottom-left arrow to instantly snap the viewport back to your real-time GPS coordinate and reset zoom to default."
        case .mapView:
            return "Tap the bottom-right reticle to toggle between the high-efficiency OLED vector radar and full map tiles."
        case .heartRate:
            return "Shows live HealthKit heart rate and pulse wave. Press and HOLD the pill button for 1.2s to toggle KIA status with your squad."
        }
    }
    
    var gestureHint: String {
        switch self {
        case .config: return "TAP ICON"
        case .tacticalCommands: return "TAP ICON"
        case .centerMap: return "TAP ICON"
        case .mapView: return "TAP ICON"
        case .heartRate: return "HOLD 1.2s"
        }
    }
}

// MARK: - Main Companion Content View
struct iOSCompanionContentView: View {
    @ObservedObject private var wcManager = WatchConnectivityManager.shared
    
    // Live Server Configs
    @State private var callsignInput: String = UserDefaults.standard.string(forKey: AppConstants.Storage.userCallsignKey) ?? ""
    @State private var roomInput: String = UserDefaults.standard.string(forKey: AppConstants.Storage.savedRoomNameKey) ?? ""
    @State private var pinInput: String = UserDefaults.standard.string(forKey: AppConstants.Storage.savedPinKey) ?? ""
    @State private var activeSquadName: String? = nil
    @State private var actionStatusText: String? = nil
    @State private var isApplyingRemoteUpdate: Bool = false
    
    @State private var selectedCallout: TacticalHUDCallout? = .tacticalCommands
    @State private var radarRotation: Double = 0.0
    @State private var pulseGlow: Bool = false
    
    private let tacticalGreen = Color(red: 0.15, green: 0.95, blue: 0.35)
    private let hudDarkBg = Color(red: 0.06, green: 0.08, blue: 0.07)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Header Section
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(wcManager.isReachable ? tacticalGreen : Color.yellow)
                                .frame(width: 8, height: 8)
                                .shadow(color: (wcManager.isReachable ? tacticalGreen : Color.yellow).opacity(0.8), radius: 4)
                            
                            Text(wcManager.isReachable ? "APPLE WATCH CONNECTED" : "APPLE WATCH STANDBY")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(wcManager.isReachable ? tacticalGreen : Color.yellow)
                                .tracking(1.5)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background((wcManager.isReachable ? tacticalGreen : Color.yellow).opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke((wcManager.isReachable ? tacticalGreen : Color.yellow).opacity(0.35), lineWidth: 1))
                        
                        Text("Tactical Companion")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Live Server Configs & Bidirectional Watch Sync")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                    
                    // MARK: - Live Server Configs Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(tacticalGreen)
                            
                            Text("SQUAD SERVER CONFIGS")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            if let status = actionStatusText {
                                Text(status)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(tacticalGreen)
                                    .transition(.opacity)
                            }
                        }
                        
                        // Callsign Field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OPERATOR CALLSIGN")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            
                            TextField("Enter Callsign (e.g. VIPER)", text: $callsignInput)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                                .onChange(of: callsignInput) { _, newValue in
                                    let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                    UserDefaults.standard.set(cleaned, forKey: AppConstants.Storage.userCallsignKey)
                                    guard !isApplyingRemoteUpdate else { return }
                                    wcManager.sendConfigUpdate(callsign: cleaned)
                                }
                        }
                        
                        // Squad Room & PIN Row
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SQUAD NAME")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                
                                TextField("Room Code", text: $roomInput)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled(true)
                                    .padding(10)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .onChange(of: roomInput) { _, newValue in
                                        let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                        UserDefaults.standard.set(cleaned, forKey: AppConstants.Storage.savedRoomNameKey)
                                        guard !isApplyingRemoteUpdate else { return }
                                        wcManager.sendConfigUpdate(roomName: cleaned)
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PIN (OPTIONAL)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                
                                TextField("4 Digits", text: $pinInput)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .keyboardType(.numberPad)
                                    .padding(10)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .onChange(of: pinInput) { _, newValue in
                                        let digits = String(newValue.filter { $0.isNumber }.prefix(4))
                                        if pinInput != digits { pinInput = digits }
                                        UserDefaults.standard.set(digits, forKey: AppConstants.Storage.savedPinKey)
                                        guard !isApplyingRemoteUpdate else { return }
                                        wcManager.sendConfigUpdate(pin: digits)
                                    }
                            }
                            .frame(width: 110)
                        }
                        
                        // Action Buttons: Host & Join
                        HStack(spacing: 10) {
                            Button(action: {
                                let cleanedRoom = roomInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                guard !cleanedRoom.isEmpty else { return }
                                wcManager.sendRoomAction(actionType: AppConstants.WatchConnectivity.ActionType.host, roomName: cleanedRoom, pin: pinInput.isEmpty ? nil : pinInput, isHosting: true)
                                triggerStatusFeedback("HOSTING '\(cleanedRoom)' ON WATCH")
                                activeSquadName = cleanedRoom
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Host Squad")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(tacticalGreen)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(roomInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Button(action: {
                                let cleanedRoom = roomInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                guard !cleanedRoom.isEmpty else { return }
                                wcManager.sendRoomAction(actionType: AppConstants.WatchConnectivity.ActionType.join, roomName: cleanedRoom, pin: pinInput.isEmpty ? nil : pinInput, isHosting: false)
                                triggerStatusFeedback("JOINING '\(cleanedRoom)' ON WATCH")
                                activeSquadName = cleanedRoom
                            }) {
                                HStack {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text("Join Squad")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.cyan)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(roomInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        
                        if activeSquadName != nil {
                            Button(action: {
                                let current = activeSquadName ?? roomInput
                                wcManager.sendRoomAction(actionType: AppConstants.WatchConnectivity.ActionType.leave, roomName: current)
                                triggerStatusFeedback("LEFT SQUAD")
                                activeSquadName = nil
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Leave Squad Room")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.18))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(UIColor.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(tacticalGreen.opacity(0.3), lineWidth: 1.5)
                            )
                    )
                    .padding(.horizontal)
                    
                    // Visual Guide / Clean Watch Display
                    VStack(spacing: 0) {
                        Image("WatchGuideDiagram")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 36, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(white: 0.4), Color(white: 0.15), Color(white: 0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal)
                    
                    // Active Callout Feature Card
                    if let active = selectedCallout {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: active.iconName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(tacticalGreen)
                                    
                                    Text(active.shortTitle)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 6) {
                                    Text(active.gestureHint)
                                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(active == .heartRate ? Color.orange : tacticalGreen)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background((active == .heartRate ? Color.orange : tacticalGreen).opacity(0.15), in: Capsule())
                                    
                                    Text(active.codeTag)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            
                            Text(active.actionInstruction)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.tertiarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(tacticalGreen.opacity(0.4), lineWidth: 1.5)
                                )
                        )
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                    
                    // Quick Reference Grid
                    VStack(alignment: .leading, spacing: 14) {
                        Text("QUICK CONTROLS DIRECTORY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        ForEach(TacticalHUDCallout.allCases) { item in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    selectedCallout = item
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedCallout == item ? tacticalGreen.opacity(0.2) : Color.primary.opacity(0.05))
                                            .frame(width: 38, height: 38)
                                        
                                        Image(systemName: item.iconName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(selectedCallout == item ? tacticalGreen : .primary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(item.shortTitle)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            
                                            Spacer()
                                            
                                            Text(item.gestureHint)
                                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                                .foregroundStyle(item == .heartRate ? Color.orange : .secondary)
                                        }
                                        
                                        Text(item.actionInstruction)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selectedCallout == item ? Color(UIColor.secondarySystemBackground) : Color(UIColor.secondarySystemBackground).opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(selectedCallout == item ? tacticalGreen.opacity(0.5) : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Hardware & Interaction Tips
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Tactical Hardware Tips", systemImage: "applewatch")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "digitalcrown.horizontal.press.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(tacticalGreen)
                                    .frame(width: 18)
                                Text("**Digital Crown:** Rotate to zoom range dynamically from 25m up to 1,000m with haptic detents.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "bolt.heart.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(tacticalGreen)
                                    .frame(width: 18)
                                Text("**Live Teammate Telemetry:** Teammate markers glide smoothly using 60fps dead reckoning.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(tacticalGreen)
                                    .frame(width: 18)
                                Text("**Independent Operation:** Radar Map operates autonomously on Apple Watch via GPS and cellular/Wi-Fi.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Radar Map")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            setupCompanionWatchConnectivity()
        }
    }
    
    private func setupCompanionWatchConnectivity() {
        wcManager.onConfigReceived = { payload in
            isApplyingRemoteUpdate = true
            if let cs = payload.callsign, callsignInput != cs {
                callsignInput = cs
                UserDefaults.standard.set(cs, forKey: AppConstants.Storage.userCallsignKey)
            }
            if let rn = payload.roomName, roomInput != rn {
                roomInput = rn
                UserDefaults.standard.set(rn, forKey: AppConstants.Storage.savedRoomNameKey)
            }
            if let pin = payload.pin, pinInput != pin {
                pinInput = pin
                UserDefaults.standard.set(pin, forKey: AppConstants.Storage.savedPinKey)
            }
            isApplyingRemoteUpdate = false
            triggerStatusFeedback("SYNCED FROM WATCH")
        }
        
        wcManager.onRoomActionReceived = { action in
            isApplyingRemoteUpdate = true
            if action.actionType == AppConstants.WatchConnectivity.ActionType.host || action.actionType == AppConstants.WatchConnectivity.ActionType.join {
                activeSquadName = action.roomName
                roomInput = action.roomName
                if let pin = action.pin { pinInput = pin }
                triggerStatusFeedback("ROOM \(action.actionType.uppercased()): '\(action.roomName)'")
            } else if action.actionType == AppConstants.WatchConnectivity.ActionType.leave || action.actionType == AppConstants.WatchConnectivity.ActionType.disband {
                activeSquadName = nil
                triggerStatusFeedback("SQUAD DISBANDED / LEFT")
            }
            isApplyingRemoteUpdate = false
        }
    }
    
    private func triggerStatusFeedback(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            actionStatusText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if actionStatusText == text {
                withAnimation(.easeInOut(duration: 0.3)) {
                    actionStatusText = nil
                }
            }
        }
    }
}
