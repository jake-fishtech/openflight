# iOS Bluetooth connection

OpenFlight can send each completed shot directly from a Raspberry Pi to the
included SwiftUI app over Bluetooth Low Energy (BLE). The connection is local,
does not require Wi-Fi or a cloud account, and is disabled unless you pass
`--ble`.

## Requirements

- Raspberry Pi with working Bluetooth and Raspberry Pi OS
- iPhone running iOS 17 or newer
- Mac with Xcode 16 or newer to build the app
- The normal OpenFlight radar setup

The app uses only Apple frameworks and has no package dependencies. The Pi
uses [Bless](https://github.com/kevincar/bless) to expose a small GATT server
through BlueZ.

## Run the Pi

The interactive setup script installs the optional BLE dependency on new
installations:

```bash
./scripts/setup/setup.sh
```

For an existing checkout, install it and start OpenFlight with BLE enabled:

```bash
uv sync --extra ble
scripts/start-kiosk.sh --ble
```

BLE startup and delivery errors are isolated from shot recording. If Bluetooth
is unavailable, the browser UI and session logger continue to work.

## Build and run the iOS app

1. Open `ios/OpenFlight.xcodeproj` in Xcode.
2. Select the `OpenFlight` target, choose your development team, and use a
   unique bundle identifier if Xcode requests one.
3. Connect an iPhone, select it as the run destination, and press Run.
4. Accept the Bluetooth permission prompt.
5. Start OpenFlight on the Pi with `--ble`.

The app scans only for the OpenFlight service, connects automatically, and
subscribes to shot notifications. Hit a shot and its metrics should replace
the empty dashboard. The most recent shot is replayed when a phone subscribes,
so a newly connected phone does not have to wait for another shot.

> The iOS Simulator can run the automated tests, but CoreBluetooth does not
> provide a useful end-to-end BLE hardware test there. Use a physical iPhone
> and Raspberry Pi for manual connection testing.

## Wire protocol

OpenFlight advertises one service and one notify-only characteristic:

| Attribute | UUID |
|---|---|
| Shot service | `B6F633F2-E6E3-45AE-84B4-968ECCA2D9C7` |
| Shot notification | `2B28F67E-9011-41D2-98ED-562B47D7A5E4` |

Each event is compact UTF-8 JSON with `schema_version: 1`. Optional
measurements are present as `null` when the active hardware could not produce
them. The version-one fields are:

```text
schema_version, event_id, timestamp, club, ball_speed_mph,
club_speed_mph, smash_factor, estimated_carry_yards,
launch_angle_vertical, launch_angle_horizontal, spin_rpm,
club_path_deg, spin_axis_deg
```

The JSON is split into conservative 20-byte notifications. Every notification
has a five-byte, big-endian header followed by up to 15 payload bytes:

| Byte(s) | Meaning |
|---|---|
| 0 | Frame version (`1`) |
| 1–2 | Unsigned 16-bit message sequence |
| 3 | Zero-based fragment index |
| 4 | Total fragment count |
| 5–19 | JSON payload fragment |

Consumers should group frames by sequence, ignore duplicate fragment indexes,
order fragments by index, and decode only after all fragments arrive. The
shared contract fixture is
`ios/OpenFlightTests/Fixtures/shot_v1.json`; both Python and Swift tests decode
that file.

## Delivery behavior

- Shot processing never waits for Bluetooth.
- The Pi keeps a bounded queue of eight unsent events and drops the oldest
  queued event if a connected phone cannot keep up.
- Disconnecting clears queued notifications but retains the latest completed
  shot for replay on the next subscription.
- The iOS app ignores a replayed event when its `event_id` is already visible.

## Security and scope

Version one intentionally has no pairing, application authentication, or
encryption layer. Enable it only where nearby Bluetooth devices receiving shot
metrics is acceptable. The service sends shot results only; it does not expose
raw radar captures, session history, settings, or control commands.

If the protocol later carries personal data or allows control of the Pi, add
authenticated pairing before extending the existing characteristic.

## Troubleshooting

**The app stays on “Looking for OpenFlight.”**

- Confirm OpenFlight was started with `--ble`.
- Run `bluetoothctl show` on the Pi and confirm `Powered: yes`.
- Keep the app in the foreground for the initial connection.
- Restart OpenFlight after changing the Pi Bluetooth configuration.

**The Pi logs `DBusError: Failed to register advertisement`.**

BlueZ returns that one message for every advertising failure, so check what
bluetoothd actually rejected:

```bash
journalctl -u bluetooth -n 20 --no-pager
```

`Failed to add advertisement: Invalid Parameters (0x0d)` means the kernel
refused the advertising parameters. Bless 0.3.0 always publishes `TxPower`,
`MinInterval`, and `MaxInterval`, which BlueZ turns into `MGMT_ADV_PARAM_*`
flags that controllers without LE Extended Advertising — including the
Raspberry Pi's — reject. OpenFlight hides those three properties before
starting the GATT server. To confirm what this adapter accepts, register the
advertisement one property group at a time:

```bash
uv run python scripts/hardware-test/test_ble_advertise.py
```

If the probe fails on `service UUID + LocalName`, the 128-bit service UUID and
the advertised name do not both fit in the 31-byte legacy advertisement. The
advertised name is the `BleShotPublisher(name=...)` default in `server.py`;
shorten it there. The iOS app scans by service UUID, so the name only affects
what other Bluetooth tools display.

**The Pi logs that Bluetooth is unavailable.**

- Run `uv sync --extra ble`.
- Confirm the BlueZ service is running with `systemctl status bluetooth`.
- Confirm the user running OpenFlight can access the system D-Bus and Bluetooth
  adapter.

**The app connects but no new shot appears.**

- Confirm the browser UI received the shot; BLE publishes only completed shot
  events.
- Look for `[BLE]` warnings in the OpenFlight terminal.
- Tap Retry in the app to disconnect, scan, and subscribe again.

## Automated tests

```bash
uv run pytest tests/test_ble_protocol.py tests/test_ble_publisher.py -v

xcodebuild test \
  -project ios/OpenFlight.xcodeproj \
  -scheme OpenFlight \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  CODE_SIGNING_ALLOWED=NO
```
