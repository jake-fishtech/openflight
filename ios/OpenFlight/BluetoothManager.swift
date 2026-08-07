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

enum BluetoothControlError: LocalizedError {
    case unavailable
    case unsupported
    case busy
    case disconnected
    case timedOut
    case invalidResponse
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Connect to OpenFlight over Bluetooth first."
        case .unsupported:
            "This OpenFlight Pi does not support phone controls. Update OpenFlight on the Pi."
        case .busy:
            "Another phone command is still in progress."
        case .disconnected:
            "Bluetooth disconnected before OpenFlight replied."
        case .timedOut:
            "OpenFlight did not reply over Bluetooth. Try again."
        case .invalidResponse:
            "OpenFlight returned an invalid Bluetooth response."
        case let .rejected(message):
            message
        }
    }
}

private final class PendingControlRequest {
    let requestID: String
    let frames: [Data]
    let continuation: CheckedContinuation<Data, Error>
    var nextFrameIndex = 0

    init(
        requestID: String,
        frames: [Data],
        continuation: CheckedContinuation<Data, Error>
    ) {
        self.requestID = requestID
        self.frames = frames
        self.continuation = continuation
    }
}

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "B6F633F2-E6E3-45AE-84B4-968ECCA2D9C7")
    static let shotCharacteristicUUID = CBUUID(
        string: "2B28F67E-9011-41D2-98ED-562B47D7A5E4"
    )
    static let controlCharacteristicUUID = CBUUID(
        string: "7E3B5D6C-7F10-4D4A-9C39-25E2B77F4A11"
    )

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var shotHistory = ShotHistory()
    @Published private(set) var supportsPhoneControls = false

    var latestShot: ShotEvent? { shotHistory.latestShot }

    private var central: CentralManaging!
    private var peripheral: CBPeripheral?
    private var shotCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var reassembler = BLEFrameReassembler()
    private var controlReassembler = BLEFrameReassembler()
    private var decoder = ShotEventDecoder()
    private var reconnectTask: Task<Void, Never>?
    private var controlTimeoutTask: Task<Void, Never>?
    private var pendingControlRequest: PendingControlRequest?
    private var controlSequence: UInt16 = 0

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
        failPendingControl(with: BluetoothControlError.disconnected)
        central.stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        shotCharacteristic = nil
        controlCharacteristic = nil
        supportsPhoneControls = false
        reassembler.reset()
        controlReassembler.reset()
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
            shotHistory.record(shot)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func submitCalibration(
        _ measurement: PhoneOrientationMeasurement
    ) async throws -> RadarCalibrationResponse {
        let requestID = UUID().uuidString.lowercased()
        let command = try BluetoothCalibrationCommand.encode(
            measurement: measurement,
            requestID: requestID
        )
        let result = try await sendControlCommand(command, requestID: requestID)
        return try JSONDecoder().decode(RadarCalibrationResponse.self, from: result)
    }

    func setClub(_ club: GolfClub) async throws -> ClubSelectionResponse {
        let requestID = UUID().uuidString.lowercased()
        let command = try BluetoothClubCommand.encode(club: club, requestID: requestID)
        let result = try await sendControlCommand(command, requestID: requestID)
        return try JSONDecoder().decode(ClubSelectionResponse.self, from: result)
    }

    private func sendControlCommand(_ command: Data, requestID: String) async throws -> Data {
        guard state == .connected, peripheral != nil else {
            throw BluetoothControlError.unavailable
        }
        guard controlCharacteristic != nil else {
            throw BluetoothControlError.unsupported
        }
        guard pendingControlRequest == nil else {
            throw BluetoothControlError.busy
        }

        let sequence = controlSequence
        controlSequence &+= 1
        let frames = try BLEFrameEncoder.frames(command, sequence: sequence)
        return try await withCheckedThrowingContinuation { continuation in
            pendingControlRequest = PendingControlRequest(
                requestID: requestID,
                frames: frames,
                continuation: continuation
            )
            controlTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.failPendingControl(with: BluetoothControlError.timedOut)
            }
            writeNextControlFrame()
        }
    }

    private func writeNextControlFrame() {
        guard let pendingControlRequest,
              pendingControlRequest.nextFrameIndex < pendingControlRequest.frames.count,
              let peripheral,
              let controlCharacteristic
        else {
            return
        }
        let frame = pendingControlRequest.frames[pendingControlRequest.nextFrameIndex]
        pendingControlRequest.nextFrameIndex += 1
        peripheral.writeValue(frame, for: controlCharacteristic, type: .withResponse)
    }

    private func receiveControlResponse(_ frame: Data) {
        do {
            guard let payload = try controlReassembler.append(frame) else { return }
            try completeControlRequest(with: payload)
        } catch {
            failPendingControl(with: error)
        }
    }

    private func completeControlRequest(with payload: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["schema_version"] as? Int == 1,
              let requestID = object["request_id"] as? String,
              let ok = object["ok"] as? Bool
        else {
            throw BluetoothControlError.invalidResponse
        }
        guard let pendingControlRequest, requestID == pendingControlRequest.requestID else {
            return
        }
        if !ok {
            throw BluetoothControlError.rejected(
                object["error"] as? String ?? "OpenFlight rejected the phone command."
            )
        }
        guard let result = object["result"] as? [String: Any] else {
            throw BluetoothControlError.invalidResponse
        }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        finishPendingControl(with: .success(resultData))
    }

    private func failPendingControl(with error: Error) {
        guard pendingControlRequest != nil else { return }
        finishPendingControl(with: .failure(error))
    }

    private func finishPendingControl(with result: Result<Data, Error>) {
        guard let pendingControlRequest else { return }
        self.pendingControlRequest = nil
        controlTimeoutTask?.cancel()
        controlTimeoutTask = nil
        controlReassembler.reset()
        pendingControlRequest.continuation.resume(with: result)
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
        failPendingControl(with: BluetoothControlError.disconnected)
        peripheral = nil
        shotCharacteristic = nil
        controlCharacteristic = nil
        supportsPhoneControls = false
        reassembler.reset()
        controlReassembler.reset()
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
        peripheral.discoverCharacteristics(
            [Self.shotCharacteristicUUID, Self.controlCharacteristicUUID],
            for: service
        )
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
        guard let shotCharacteristic = service.characteristics?.first(where: {
            $0.uuid == Self.shotCharacteristicUUID
        }) else {
            state = .error("OpenFlight shot notifications were not found")
            return
        }
        self.shotCharacteristic = shotCharacteristic
        controlCharacteristic = service.characteristics?.first(where: {
            $0.uuid == Self.controlCharacteristicUUID
        })
        peripheral.setNotifyValue(true, for: shotCharacteristic)
        if let controlCharacteristic {
            peripheral.setNotifyValue(true, for: controlCharacteristic)
        }
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            if characteristic.uuid == Self.controlCharacteristicUUID {
                controlCharacteristic = nil
                supportsPhoneControls = false
                failPendingControl(with: error)
            } else {
                state = .error(error.localizedDescription)
            }
        } else if characteristic.isNotifying {
            if characteristic.uuid == Self.shotCharacteristicUUID {
                state = .connected
            } else if characteristic.uuid == Self.controlCharacteristicUUID {
                supportsPhoneControls = true
            }
        }
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            if characteristic.uuid == Self.controlCharacteristicUUID {
                failPendingControl(with: error)
            } else {
                state = .error(error.localizedDescription)
            }
            return
        }
        guard let value = characteristic.value else { return }
        if characteristic.uuid == Self.controlCharacteristicUUID {
            receiveControlResponse(value)
        } else if characteristic.uuid == Self.shotCharacteristicUUID {
            receive(value)
        }
    }

    func peripheral(
        _: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.controlCharacteristicUUID else { return }
        if let error {
            failPendingControl(with: error)
        } else {
            writeNextControlFrame()
        }
    }
}
