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
                            gameState.joinRoom(id: room.id, name: room.name) { success in
                                if success {
                                    dismiss()
                                }
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(room.name)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                    
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
                    #if os(iOS)
                    TextField("Squad Name", text: $manualRoomCode)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .submitLabel(.done)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.characters)
                        .disabled(gameState.isJoining || gameState.firebaseManager.isConnected)
                    
                    TextField("PIN (4 digits)", text: $manualPin)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .submitLabel(.done)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .disabled(gameState.isJoining || gameState.firebaseManager.isConnected)
                        .onChange(of: manualPin) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count > 4 {
                                manualPin = String(filtered.prefix(4))
                            } else if filtered != newValue {
                                manualPin = filtered
                            }
                        }
                    #else
                    TextField("Squad Name", text: $manualRoomCode)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .submitLabel(.done)
                        .disabled(gameState.isJoining || gameState.firebaseManager.isConnected)
                    
                    TextField("PIN (4 digits)", text: $manualPin)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .submitLabel(.done)
                        .disabled(gameState.isJoining || gameState.firebaseManager.isConnected)
                        .onChange(of: manualPin) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count > 4 {
                                manualPin = String(filtered.prefix(4))
                            } else if filtered != newValue {
                                manualPin = filtered
                            }
                        }
                    #endif
                    
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
        }
        .onDisappear {
            gameState.bluetoothManager.stopScanning()
        }
    }
}
