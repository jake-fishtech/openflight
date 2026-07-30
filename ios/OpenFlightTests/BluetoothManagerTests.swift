import CoreBluetooth
import XCTest
@testable import OpenFlight

@MainActor
final class BluetoothManagerTests: XCTestCase {
    func testPoweredOnCentralStartsServiceFilteredScan() {
        let central = FakeCentral(state: .poweredOn)
        let manager = BluetoothManager(central: central)

        manager.start()

        XCTAssertEqual(manager.state, .scanning)
        XCTAssertEqual(central.scannedServices, [BluetoothManager.serviceUUID])
    }

    func testUnavailableStatesAreActionable() {
        let central = FakeCentral(state: .poweredOff)
        let manager = BluetoothManager(central: central)

        manager.start()

        XCTAssertEqual(manager.state, .unavailable("Bluetooth is turned off"))
        XCTAssertTrue(manager.state.canRetry)
    }

    func testReceivePublishesCompletedSharedFixture() throws {
        let manager = BluetoothManager(central: FakeCentral(state: .poweredOn))
        let payload = try sharedShotFixture()

        for frame in makeBLEFrames(payload, sequence: 10) {
            manager.receive(frame)
        }

        XCTAssertEqual(manager.latestShot?.ballSpeedMPH, 151.4)
        XCTAssertEqual(
            manager.latestShot?.eventID.uuidString,
            "B0D91F0A-7950-4D7E-9DD5-AF9777C190E1"
        )
    }

    func testReceiveIgnoresReplayWithSameEventID() throws {
        let manager = BluetoothManager(central: FakeCentral(state: .poweredOn))
        let original = try sharedShotFixture()
        var replayObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        replayObject["ball_speed_mph"] = 199.0
        let changedReplay = try JSONSerialization.data(withJSONObject: replayObject)

        for frame in makeBLEFrames(original, sequence: 10) {
            manager.receive(frame)
        }
        for frame in makeBLEFrames(changedReplay, sequence: 11) {
            manager.receive(frame)
        }

        XCTAssertEqual(manager.latestShot?.ballSpeedMPH, 151.4)
    }
}

private final class FakeCentral: CentralManaging {
    let state: CBManagerState
    var scannedServices: [CBUUID]?

    init(state: CBManagerState) {
        self.state = state
    }

    func scanForPeripherals(
        withServices serviceUUIDs: [CBUUID]?,
        options _: [String: Any]?
    ) {
        scannedServices = serviceUUIDs
    }

    func stopScan() {}
    func connect(_: CBPeripheral, options _: [String: Any]?) {}
    func cancelPeripheralConnection(_: CBPeripheral) {}
}
