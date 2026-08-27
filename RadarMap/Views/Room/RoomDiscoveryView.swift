import SwiftUI

public struct RoomDiscoveryView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var manualRoomCode: String = ""
    @State private var manualPin: String = ""
    @State private var showCreateRoomSheet: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                // Host Squad Section
                Section {
                    Button(action: {
                        showCreateRoomSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Host New Squad")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // BLE Scanner Status Section
                Section(header: Text("Nearby BLE Radar").font(.system(size: 9))) {
                    if gameState.bluetoothManager.isScanning {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Scanning for squads...")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if gameState.bluetoothManager.discoveredRooms.isEmpty && !gameState.bluetoothManager.isScanning {
                        Text("No nearby squads found.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    
                    ForEach(gameState.bluetoothManager.discoveredRooms) { room in
                        Button(action: {
                            let pin = manualPin.trimmingCharacters(in: .whitespacesAndNewlines)
                            gameState.joinRoom(id: room.id, name: room.name, pin: pin.isEmpty ? nil : pin) { success in
                                if success {
                                    dismiss()
                                }
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(room.name)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                        if room.hasPin {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(.yellow)
                                        }
                                    }
                                    
                                    Text("Code: \(room.id)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                // Signal strength icon
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                }
                
                // Direct Room Entry Section
                Section(header: Text("Direct Join").font(.system(size: 9))) {
                    TextField("Squad Name", text: $manualRoomCode)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor((gameState.isJoining || gameState.firebaseManager.isConnected) ? .gray : .primary)
                        .opacity((gameState.isJoining || gameState.firebaseManager.isConnected) ? 0.6 : 1.0)
                        .lineLimit(1)
                        .submitLabel(.done)
                        .autocorrectionDisabled(true)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .disabled(gameState.isJoining || gameState.firebaseManager.isConnected)
                        .onChange(of: manualRoomCode) { _, newValue in
                            gameState.savedRoomName = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    
                    TextField("PIN (4 digits)", text: $manualPin)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor((gameState.isJoining || gameState.firebaseManager.isConnected) ? .gray : .primary)
                        .opacity((gameState.isJoining || gameState.firebaseManager.isConnected) ? 0.6 : 1.0)
                        .lineLimit(1)
                        .submitLabel(.done)
                        .textContentType(.oneTimeCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .disabled(gameState.isJoining || gameState.firebaseManager.isConnected)
                        .onChange(of: manualPin) { _, newValue in
                            let sanitized = GameStateManager.sanitizePinInput(newValue)
                            if manualPin != sanitized {
                                manualPin = sanitized
                            }
                            gameState.savedPin = manualPin
                        }
                    
                    Button(action: {
                        let cleaned = manualRoomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        let pin = manualPin.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            gameState.joinRoom(id: cleaned, name: "Squad \(cleaned)", pin: pin.isEmpty ? nil : pin) { success in
                                if success {
                                    dismiss()
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Spacer()
                            if gameState.isJoining {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Joining...")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.cyan)
                            } else {
                                Text("Join Squad")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.cyan)
                            }
                            Spacer()
                        }
                    }
                    .disabled(manualRoomCode.isEmpty || gameState.isJoining || gameState.firebaseManager.isConnected)
                }
            }
            .navigationTitle("Squad Operations")
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
            .sheet(isPresented: $showCreateRoomSheet) {
                CreateRoomView()
                    .environmentObject(gameState)
            }
            .onChange(of: gameState.firebaseManager.activeRoom != nil) { _, inRoom in
                if inRoom {
                    dismiss()
                }
            }
        }
        .onAppear {
            gameState.bluetoothManager.startScanning()
            if manualRoomCode.isEmpty {
                manualRoomCode = gameState.savedRoomName
            }
            if manualPin.isEmpty {
                manualPin = gameState.savedPin
            }
        }
        .onDisappear {
            gameState.bluetoothManager.stopScanning()
        }
    }
}
