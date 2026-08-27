import Foundation
import CoreBluetooth
import Combine

public struct DiscoveredRoom: Identifiable, Equatable {
    public let id: String          // Room ID e.g. "BRAVO-4"
    public let name: String        // Room Name
    public let rssi: Int           // Signal strength
    public let discoveredAt: Date
    public let peripheral: CBPeripheral?
    public var hasPin: Bool
    
    public init(
        id: String,
        name: String,
        rssi: Int,
        discoveredAt: Date,
        peripheral: CBPeripheral?,
        hasPin: Bool = false
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.discoveredAt = discoveredAt
        self.peripheral = peripheral
        self.hasPin = hasPin
    }
    
    public static func == (lhs: DiscoveredRoom, rhs: DiscoveredRoom) -> Bool {
        lhs.id == rhs.id
    }
}

public final class BluetoothDiscoveryManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    public static let radarServiceUUID = AppConstants.Network.Bluetooth.radarServiceUUID
    public static let roomDataCharacteristicUUID = AppConstants.Network.Bluetooth.roomDataCharacteristicUUID
    
    @Published public var discoveredRooms: [DiscoveredRoom] = []
    @Published public var isScanning: Bool = false
    @Published public var isAdvertising: Bool = false
    @Published public var bluetoothState: CBManagerState = .unknown
    
    private var centralManager: CBCentralManager!
    #if !os(watchOS)
    private var peripheralManager: CBPeripheralManager?
    #endif
    private var currentRoomToAdvertise: SquadRoom?
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        #if !os(watchOS)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        #endif
    }
    
    // MARK: - Central (Scanning for Rooms)
    
    public func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredRooms.removeAll()
        centralManager.scanForPeripherals(
            withServices: [BluetoothDiscoveryManager.radarServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }
    
    // MARK: - Peripheral (Advertising Room as Host)
    
    public func startAdvertisingRoom(_ room: SquadRoom) {
        self.currentRoomToAdvertise = room
        #if !os(watchOS)
        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn else { return }
        
        let pinFlag = room.hasPin ? "1" : "0"
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BluetoothDiscoveryManager.radarServiceUUID],
            CBAdvertisementDataLocalNameKey: "\(AppConstants.Network.Bluetooth.advertisementPrefix)\(room.id):\(room.name):\(pinFlag)"
        ]
        
        peripheralManager.stopAdvertising()
        peripheralManager.startAdvertising(advertisementData)
        #endif
        isAdvertising = true
    }
    
    public func stopAdvertising() {
        #if !os(watchOS)
        peripheralManager?.stopAdvertising()
        #endif
        isAdvertising = false
        currentRoomToAdvertise = nil
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.bluetoothState = central.state
        if central.state == .poweredOn && isScanning {
            startScanning()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? AppConstants.Network.Bluetooth.defaultLocalName
        
        // Parse payload e.g. "RM:ROOM_ID:ROOM_NAME" or "RM:ROOM_ID:ROOM_NAME:PIN_FLAG"
        var roomId = peripheral.identifier.uuidString.prefix(6).uppercased()
        var roomName = localName
        var hasPin = false
        
        let prefix = AppConstants.Network.Bluetooth.advertisementPrefix
        if localName.hasPrefix(prefix) {
            let parts = localName.split(separator: ":")
            if parts.count >= 2 {
                roomId = String(parts[1])
            }
            if parts.count >= 3 {
                roomName = String(parts[2])
            }
            if parts.count >= 4 {
                hasPin = (parts[3] == "1" || parts[3] == "true")
            }
        }
        
        let room = DiscoveredRoom(
            id: String(roomId),
            name: roomName,
            rssi: RSSI.intValue,
            discoveredAt: Date(),
            peripheral: peripheral,
            hasPin: hasPin
        )
        
        DispatchQueue.main.async {
            if let index = self.discoveredRooms.firstIndex(where: { $0.id == room.id }) {
                self.discoveredRooms[index] = room
            } else {
                self.discoveredRooms.append(room)
            }
        }
    }
}

#if !os(watchOS)
extension BluetoothDiscoveryManager: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn, let room = currentRoomToAdvertise {
            startAdvertisingRoom(room)
        }
    }
}
#endif
