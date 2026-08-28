import SwiftUI

public struct CreateRoomView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var roomName: String = ""
    @State private var roomPassword: String = ""
    @State private var squadCapacity: Int = AppConstants.Subscription.freeTierMaxCapacity
    @State private var showPaywall: Bool = false
    @State private var navigateToLobby: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // Room Name Field
                    TextField("Squad Name", text: $roomName)
                        .font(.system(size: 12))
                        .foregroundColor((gameState.isHosting || gameState.firebaseManager.isConnected) ? .gray : .primary)
                        .opacity((gameState.isHosting || gameState.firebaseManager.isConnected) ? 0.6 : 1.0)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .lineLimit(1)
                        .submitLabel(.done)
                        .autocorrectionDisabled(true)
                        .disabled(gameState.isHosting || gameState.firebaseManager.isConnected)
                        .onChange(of: roomName) { _, newValue in
                            gameState.savedRoomName = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    
                    // Squad Password / PIN Field (4-digit number only)
                    TextField("Squad PIN (4 digits, optional)", text: $roomPassword)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor((gameState.isHosting || gameState.firebaseManager.isConnected) ? .gray : .primary)
                        .opacity((gameState.isHosting || gameState.firebaseManager.isConnected) ? 0.6 : 1.0)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .lineLimit(1)
                        .submitLabel(.done)
                        .textContentType(.oneTimeCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .disabled(gameState.isHosting || gameState.firebaseManager.isConnected)
                        .onChange(of: roomPassword) { _, newValue in
                            let sanitized = GameStateManager.sanitizePinInput(newValue)
                            if roomPassword != sanitized {
                                roomPassword = sanitized
                            }
                            gameState.savedPin = roomPassword
                        }
                    
                    // Capacity Tier Status (4 or 999)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("SQUAD CAPACITY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray)
                            Spacer()
                            
                            if gameState.subscriptionManager.hasUnlimitedSquadUnlock {
                                Text("Unlimited (Squad Leader Pro)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                            } else {
                                Text("\(AppConstants.Subscription.freeTierMaxCapacity) operators (Free)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                            }
                        }
                        
                        if !gameState.subscriptionManager.hasUnlimitedSquadUnlock {
                            Button(action: {
                                showPaywall = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                    Text("Upgrade to Unlimited Players (\(AppConstants.Subscription.lifetimePriceString))")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.2))
                                .foregroundColor(.yellow)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                    
                    Button(action: {
                        gameState.hostRoom(name: roomName, pin: roomPassword.isEmpty ? nil : roomPassword) { success in
                            if success {
                                dismiss()
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Host Squad")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 6)
            }
            .navigationTitle("Host Room")
            #if os(watchOS) || os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
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
            .onChange(of: gameState.firebaseManager.activeRoom != nil) { _, inRoom in
                if inRoom {
                    dismiss()
                }
            }
            .onChange(of: gameState.savedRoomName) { _, newRoom in
                if roomName != newRoom {
                    roomName = newRoom
                }
            }
            .onChange(of: gameState.savedPin) { _, newPin in
                if roomPassword != newPin {
                    roomPassword = newPin
                }
            }
            .onAppear {
                if roomName.isEmpty {
                    roomName = gameState.savedRoomName
                }
                if roomPassword.isEmpty {
                    roomPassword = gameState.savedPin
                }
            }
        }
    }
}

