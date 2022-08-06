import Foundation
import CoreBluetooth

class BluetoothScanner: NSObject, CBCentralManagerDelegate {

    private var centralManager: CBCentralManager!
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("state: \(central.state)")
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil)
            print("Started scan")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print(advertisementData)
    }
}

class BluetoothService: NSObject, CBPeripheralManagerDelegate {
    private var service: CBUUID!
    private var peripheralManager : CBPeripheralManager!
    var scanner = BluetoothScanner()
    
    let readData = "readdata".data(using: .utf8)
    let nrwData = "notifywritedata".data(using: .utf8)
    
    func start() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func addServices() {
        let myChar1 = CBMutableCharacteristic(type: CBUUID(nsuuid: UUID()), properties: [.write], value: nil, permissions: [.writeable])
        let myChar2 = CBMutableCharacteristic(type: CBUUID(nsuuid: UUID()), properties: [.read], value: readData, permissions: [.readable])
        service = CBUUID(nsuuid: UUID())
        let myService = CBMutableService(type: service, primary: true)
        myService.characteristics = [myChar1, myChar2]
        peripheralManager.add(myService)
        startAdvertising()
        print("Servce UUID: \(myService.uuid.description)")
        print("Char1: \(myChar1.uuid.description)")
        print("Char2: \(myChar2.uuid.description)")
    }
    
    func startAdvertising() {
        print("MESSAGE LABEL: \(CBAdvertisementDataLocalNameKey)")
        peripheralManager.startAdvertising([
            "abchello": "defhello",
            CBAdvertisementDataLocalNameKey: "BLEPeripheralAppAirdash",
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
        print("READ VALUE: \(request.characteristic.description)")
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
