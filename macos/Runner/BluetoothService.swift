import Foundation
import CoreBluetooth

class BluetoothService: NSObject, CBPeripheralManagerDelegate {
    private var service: CBUUID!
    private let value = "AD34E"
    private var peripheralManager : CBPeripheralManager!
    
    func start() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func addServices() {
        let valueData = value.data(using: .utf8)
        let myChar1 = CBMutableCharacteristic(type: CBUUID(nsuuid: UUID()), properties: [.notify, .write, .read], value: nil, permissions: [.readable, .writeable])
        let myChar2 = CBMutableCharacteristic(type: CBUUID(nsuuid: UUID()), properties: [.read], value: valueData, permissions: [.readable])
        service = CBUUID(nsuuid: UUID())
        let myService = CBMutableService(type: service, primary: true)
        myService.characteristics = [myChar1, myChar2]
        peripheralManager.add(myService)
        startAdvertising()
        print("Servce UUID: \(myService.uuid.uuidStr)")
        print("Char1: \(myChar1.uuid.uuidStr)")
        print("Char2: \(myChar2.uuid.uuidStr)")
    }
    
    func startAdvertising() {
        print("MESSAGE LABEL: \("Advertising Data")")
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "BLEPeripheralApp",
            CBAdvertisementDataServiceUUIDsKey: [service]
        ])
        print("Started Advertising")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        print("MESSAGE LABEL: \("Writing Data")")
        if let value = requests.first?.value {
            print("WRITE VALUE: \(hexString(of: value))")
            //Perform here your additional operations on the data.
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("MESSAGE LABEL: \("Data getting Read")")
        print("READ VALUE: \(value)")
        // Perform your additional operations here
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
            case .unknown:
                print("Bluetooth Device is UNKNOWN")
            case .unsupported:
                print("Bluetooth Device is UNSUPPORTED")
            case .unauthorized:
                print("Bluetooth Device is UNAUTHORIZED")
            case .resetting:
                print("Bluetooth Device is RESETTING")
            case .poweredOff:
                print("Bluetooth Device is POWERED OFF")
            case .poweredOn:
                print("Bluetooth Device is POWERED ON")
                addServices()
            @unknown default:
                print("Unknown State")
            }
    }
    
    func hexString(of data: Data) -> String {
        return data.map { String(format: "%02hhx", $0) }.joined()
    }
    
}
