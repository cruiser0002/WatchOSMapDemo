import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Environment(\.dismiss) private var dismiss
    
    // Form fields
    @State private var callsignInput: String = ""
    @State private var squadName: String = ""
    @State private var squadPin: String = ""
    
    // Focus states for auto-scrolling on keyboard appearance
    private enum FocusField: Hashable {
        case callsign
        case squadName
        case pin
    }
    @FocusState private var focusedField: FocusField?
    
    // Paywall state
    @State private var showPaywall: Bool = false
    
    public init() {}
    
    private var squadMembers: [SquadMember] {
        guard let room = gameState.firebaseManager.activeRoom else { return [] }
        return Array(room.members.values)
    }
    
    private var isConnected: Bool {
        gameState.firebaseManager.isConnected && gameState.firebaseManager.activeRoom != nil
    }
    
    private var isHost: Bool {
        isConnected && gameState.isCurrentMemberHost
    }
    
    private var isClient: Bool {
        isConnected && !gameState.isCurrentMemberHost
    }
    
    private var isBusy: Bool {
        isConnected || gameState.isHosting || gameState.isInitiatingHost || gameState.isJoining
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    callsignField
                    squadNameField
                    pinField
                    hostButton
                    joinButton
                }
                
                radarColorSection
                
                paywallSection
                
                if let room = gameState.firebaseManager.activeRoom {
                    rosterSection(room: room)
                }
            }
            .navigationTitle("Config")
            #if os(watchOS) || os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                callsignInput = gameState.myCallsign
                if let room = gameState.firebaseManager.activeRoom {
                    squadName = room.name
                    squadPin = ""
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(gameState)
            }
            .sheet(isPresented: $gameState.showPaywallSheet) {
                PaywallView()
                    .environmentObject(gameState)
            }
            .alert(isPresented: Binding(
                get: { gameState.errorMessage != nil },
                set: { if !$0 { gameState.errorMessage = nil } }
            )) {
                Alert(
                    title: Text("Squad Error"),
                    message: Text(gameState.errorMessage ?? "An error occurred."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onChange(of: focusedField) { _, newField in
                if let field = newField {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var callsignField: some View {
        #if os(iOS) || os(watchOS)
        TextField("Callsign", text: $callsignInput)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .submitLabel(.done)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .callsign)
            .id(FocusField.callsign)
            .disabled(isBusy)
            .onChange(of: callsignInput) { _, newValue in
                let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !filtered.isEmpty {
                    gameState.myCallsign = filtered
                }
            }
        #else
        TextField("Callsign", text: $callsignInput)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .callsign)
            .id(FocusField.callsign)
            .disabled(isBusy)
            .onChange(of: callsignInput) { _, newValue in
                let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !filtered.isEmpty {
                    gameState.myCallsign = filtered
                }
            }
        #endif
    }
    
    @ViewBuilder
    private var squadNameField: some View {
        #if os(iOS) || os(watchOS)
        TextField("Squad Name", text: $squadName)
            .font(.system(size: 11))
            .lineLimit(1)
            .submitLabel(.done)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .squadName)
            .id(FocusField.squadName)
            .disabled(isBusy)
        #else
        TextField("Squad Name", text: $squadName)
            .font(.system(size: 11))
            .lineLimit(1)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .squadName)
            .id(FocusField.squadName)
            .disabled(isBusy)
        #endif
    }
    
    @ViewBuilder
    private var pinField: some View {
        #if os(iOS)
        TextField("Squad PIN (4 digits, optional)", text: $squadPin)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .submitLabel(.done)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focusedField, equals: .pin)
            .id(FocusField.pin)
            .disabled(isBusy)
            .onChange(of: squadPin) { _, newValue in
                let filtered = newValue.filter { $0.isNumber }
                if filtered.count > 4 {
                    squadPin = String(filtered.prefix(4))
                } else if filtered != newValue {
                    squadPin = filtered
                }
            }
        #else
        TextField("Squad PIN (4 digits, optional)", text: $squadPin)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .submitLabel(.done)
            .focused($focusedField, equals: .pin)
            .id(FocusField.pin)
            .disabled(isBusy)
            .onChange(of: squadPin) { _, newValue in
                let filtered = newValue.filter { $0.isNumber }
                if filtered.count > 4 {
                    squadPin = String(filtered.prefix(4))
                } else if filtered != newValue {
                    squadPin = filtered
                }
            }
        #endif
    }
    
    @ViewBuilder
    private var hostButton: some View {
        if isHost {
            Button(action: {
                gameState.leaveCurrentRoom()
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                    Text("Disband")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: {
                let name = squadName.trimmingCharacters(in: .whitespacesAndNewlines)
                let pin = squadPin.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = gameState.hostRoom(name: name.isEmpty ? "Alpha Squad" : name, pin: pin.isEmpty ? nil : pin)
            }) {
                HStack(spacing: 6) {
                    Spacer()
                    if gameState.isInitiatingHost {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.black)
                        Text("Initiating...")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Host")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor((gameState.isJoining || isClient) ? .gray : .black)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .background((gameState.isJoining || isClient) ? Color.gray.opacity(0.3) : Color.green)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(gameState.isJoining || gameState.isInitiatingHost || isClient)
        }
    }
    
    @ViewBuilder
    private var joinButton: some View {
        if isClient {
            Button(action: {
                gameState.leaveCurrentRoom()
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Leave")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: {
                let name = squadName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let pin = squadPin.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    gameState.joinRoom(id: name, name: name, pin: pin.isEmpty ? nil : pin)
                }
            }) {
                HStack(spacing: 6) {
                    Spacer()
                    if gameState.isJoining {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.black)
                        Text("Joining...")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                    } else {
                        Image(systemName: "person.badge.plus")
                        Text("Join")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor((gameState.isInitiatingHost || isHost || squadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? .gray : .black)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .background((gameState.isInitiatingHost || isHost || squadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? Color.gray.opacity(0.3) : Color.cyan)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(gameState.isInitiatingHost || gameState.isJoining || isHost || squadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    @ViewBuilder
    private var radarColorSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { gameState.radarColorTheme == .red },
                set: { gameState.radarColorTheme = $0 ? .red : .green }
            )) {
                HStack {
                    Text("Radar color")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(gameState.radarColorTheme.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(gameState.radarColorTheme.color)
                }
            }
        }
    }
    
    @ViewBuilder
    private var paywallSection: some View {
        Section {
            if gameState.subscriptionManager.hasUnlimitedSquadUnlock {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.yellow)
                    Text("Squad Leader Unlocked")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                }
            } else {
                Button(action: {
                    showPaywall = true
                }) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.yellow)
                        Text("Unlock squad leader")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                        Spacer()
                        Text(SubscriptionManager.lifetimePriceString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func rosterSection(room: SquadRoom) -> some View {
        Section(header: Text("Squad Roster (\(room.memberCount))").font(.system(size: 9))) {
            ForEach(squadMembers) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(member.callsign)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(member.id == gameState.myMemberId ? .cyan : .white)
                            
                            if member.isHost {
                                Text("HOST")
                                    .font(.system(size: 7, weight: .bold))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.yellow.opacity(0.3))
                                    .foregroundColor(.yellow)
                                    .cornerRadius(3)
                            }
                        }
                        
                        Text("Heading: \(Int(member.heading))°")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundColor(member.heartRateZoneColor)
                        Text("\(Int(member.heartRate))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                }
            }
        }
    }
}

