@preconcurrency import CoreBluetooth
import Foundation

protocol CentralManaging: AnyObject {
    var state: CBManagerState { get }
    func scanForPeripherals(
        withServices serviceUUIDs: [CBUUID]?,
        options: [String: Any]?
    )
    func stopScan()
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
    func cancelPeripheralConnection(_ peripheral: CBPeripheral)
}

extension CBCentralManager: CentralManaging {}

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "B6F633F2-E6E3-45AE-84B4-968ECCA2D9C7")
    static let shotCharacteristicUUID = CBUUID(
        string: "2B28F67E-9011-41D2-98ED-562B47D7A5E4"
    )

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var latestShot: ShotEvent?

    private var central: CentralManaging!
    private var peripheral: CBPeripheral?
    private var shotCharacteristic: CBCharacteristic?
    private var reassembler = BLEFrameReassembler()
    private var decoder = ShotEventDecoder()
    private var reconnectTask: Task<Void, Never>?

    override convenience init() {
        self.init(central: nil)
    }

    init(central: CentralManaging?) {
        super.init()
        self.central = central ?? CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        guard central.state == .poweredOn else {
            handleCentralState(central.state)
            return
        }
        startScanning()
    }

    func retry() {
        reconnectTask?.cancel()
        disconnect()
        start()
    }

    func disconnect() {
        reconnectTask?.cancel()
        central.stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        shotCharacteristic = nil
        reassembler.reset()
        state = .idle
    }

    func handleCentralState(_ centralState: CBManagerState) {
        switch centralState {
        case .poweredOn:
            startScanning()
        case .poweredOff:
            state = .unavailable("Bluetooth is turned off")
        case .unauthorized:
            state = .unavailable("Bluetooth permission is required")
        case .unsupported:
            state = .unavailable("Bluetooth LE is not supported")
        case .resetting:
            state = .unavailable("Bluetooth is resetting")
        case .unknown:
            state = .idle
        @unknown default:
            state = .unavailable("Bluetooth is unavailable")
        }
    }

    private func startScanning() {
        guard central.state == .poweredOn else {
            handleCentralState(central.state)
            return
        }
        reconnectTask?.cancel()
        state = .scanning
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    func receive(_ frame: Data) {
        do {
            guard let payload = try reassembler.append(frame),
                  let shot = try decoder.decode(payload)
            else {
                return
            }
            latestShot = shot
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

extension BluetoothManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleCentralState(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        central.stopScan()
        self.peripheral = peripheral
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .discovering
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _: CBCentralManager,
        didFailToConnect _: CBPeripheral,
        error: Error?
    ) {
        state = .error(error?.localizedDescription ?? "Could not connect to OpenFlight")
        scheduleReconnect()
    }

    func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error _: Error?
    ) {
        peripheral = nil
        shotCharacteristic = nil
        reassembler.reset()
        state = .scanning
        scheduleReconnect()
    }
}

extension BluetoothManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            state = .error("OpenFlight BLE service was not found")
            return
        }
        peripheral.discoverCharacteristics([Self.shotCharacteristicUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid == Self.shotCharacteristicUUID
        }) else {
            state = .error("OpenFlight shot notifications were not found")
            return
        }
        shotCharacteristic = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            state = .error(error.localizedDescription)
        } else if characteristic.uuid == Self.shotCharacteristicUUID,
                  characteristic.isNotifying
        {
            state = .connected
        }
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        guard characteristic.uuid == Self.shotCharacteristicUUID,
              let value = characteristic.value
        else {
            return
        }
        receive(value)
    }
}
