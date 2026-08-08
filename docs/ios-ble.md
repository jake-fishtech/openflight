# iOS app connection

> **BLE blocker — check the Raspberry Pi kernel first:** Raspberry Pi kernel
> `6.18.34+rpt-rpi-2712` has a confirmed regression that rejects every BLE
> advertisement. Run `uname -r` on the Pi. If it reports that version, use the
> Wi-Fi transport or boot a working kernel such as 6.12.x; there is no userspace
> workaround. See the [full diagnosis](#known-bad-raspberry-pi-kernel-61834rpt-rpi-2712).

OpenFlight sends each completed shot from a Raspberry Pi to the included SwiftUI
app over one of two local transports, chosen with the picker at the top of the
app. Both carry the identical versioned payload described below, so the app
behaves the same either way.

| Transport | Pi setup | Use it when |
|---|---|---|
| **Bluetooth** | start with `--ble` | No Wi-Fi at all, or the phone is not on the Pi's network |
| **Wi-Fi** | always on | The phone and Pi share a network, or Bluetooth advertising is unavailable |

Wi-Fi needs no flag: it streams from the same HTTP server that serves the
browser UI, and exposes nothing the browser UI does not already broadcast.

## Requirements

- Raspberry Pi running Raspberry Pi OS (working Bluetooth only for the BLE transport)
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

## Wi-Fi transport

The server streams shots as [Server-Sent Events](https://developer.mozilla.org/docs/Web/API/Server-sent_events)
at `/api/shots/stream`. Check it from any machine on the network before
involving a phone:

```bash
curl -N http://raspberrypi.local:8080/api/shots/stream
```

A connection opens with a `: ping` comment, replays the most recent shot if
there is one, then emits one `event: shot` message per shot with a heartbeat
every 15 seconds while idle:

```text
: ping

event: shot
data: {"ball_speed_mph":151.4,"club":"driver",...,"schema_version":1}
```

In the app, pick **Wi-Fi** and enter the Pi's address. `raspberrypi.local:8080`
is the default and works on a stock Raspberry Pi OS install, which publishes its
hostname over mDNS; if you renamed the Pi, use `<hostname>.local:8080` or its IP.
The port defaults to 8080 when you leave it off. The app reconnects on its own
with backoff, and iOS asks once for permission to talk to devices on the local
network.

The server accepts up to eight simultaneous stream clients and answers `503`
beyond that, so a forgotten `curl` cannot crowd out a phone.

## Build and run the iOS app

For complete Xcode, signing, physical-device, simulator, testing, and
troubleshooting instructions, start with [`ios/README.md`](../ios/README.md).

1. Open `ios/OpenFlight.xcodeproj` in Xcode.
2. Select the `OpenFlight` target, choose your development team, and use a
   unique bundle identifier if Xcode requests one.
3. Connect an iPhone, select it as the run destination, and press Run.
4. Accept the Bluetooth permission prompt.
5. Start OpenFlight on the Pi, adding `--ble` if you want the Bluetooth
   transport.

Over Bluetooth the app scans only for the OpenFlight service, connects
automatically, and subscribes to shot and control notifications. Over Wi-Fi it
opens the shot stream and keeps it open. Either way, hit a shot and its metrics
should replace the empty dashboard. The most recent shot is replayed when a
phone connects, so a newly connected phone does not have to wait for another
shot.

## Select the club from the iPhone

Use **Club for next shot** on the dashboard to select any supported wood,
hybrid, iron, or wedge. OpenFlight applies the club to subsequent shots and
confirms the change before the app updates its saved selection. The app sends
the change over the currently selected transport:

- Bluetooth uses the framed control characteristic described below.
- Wi-Fi sends `POST /api/club` with `{"club":"7-iron"}`.

The browser UI and simulator integrations use the same server operation, so a
phone club change affects the same launch, spin, and carry processing state.

> The iOS Simulator can run the automated tests, but CoreBluetooth does not
> provide a useful end-to-end BLE hardware test there. Use a physical iPhone
> and Raspberry Pi for manual connection testing.

## Calibrate TI radar tilt with the iPhone

The dashboard's **Calibrate TI Radar** button opens a guided mount-angle tool.
It sends the measurement over whichever transport is selected on the dashboard.

1. Start OpenFlight with the IWR6843 enabled. Add `--ble` for Bluetooth, or
   connect the phone to the Pi's network for Wi-Fi.
2. Remove the phone case. Hold the phone upright in portrait with its back flat
   against a straight reference surface parallel to the TI antenna face. Keep
   the screen facing the target and avoid resting on the camera bump.
3. Keep the radar and phone still while the app averages 120 gravity samples
   over about two seconds.
4. Confirm left/right roll is within 3 degrees, then tap **Apply Calibration**.

While the phone is moving, the angle cards are labeled **Live sensor reading**
and show the latest Core Motion gravity angles without the two-second averaging
lag. Once the sample window passes the stability and roll checks, the cards turn
green and switch to the **Stable 2-second average** that will actually be sent
to OpenFlight.

The app sends the averaged gravity vector, calculated mount tilt and roll,
sample count, and stability statistics through the BLE control characteristic
or `POST /api/calibration/iwr6843/orientation`. Both paths call the same server
operation. The Pi independently recomputes the angles from gravity and rejects
inconsistent or unstable measurements. If the optional enclosure LIS3DH is
active, OpenFlight subtracts its current calibrated enclosure pitch so the
saved value remains the TI antenna's angle relative to the enclosure. Otherwise,
the measured phone tilt is used directly.

The applied value takes effect immediately and is saved at
`~/.config/openflight/iwr6843_phone_orientation.json`. It is restored on startup
unless an explicit `--iwr6843-tilt-deg` value is supplied, which always wins.
Session logs record the change with source `ios_companion`.

This process measures pitch and verifies roll. It deliberately does not change
`--iwr6843-azimuth-offset-deg`: an accelerometer cannot establish yaw relative
to the target line, and phone compass readings near radar electronics are not a
precision substitute for target-line alignment.

## Wire protocol

Both transports carry the same JSON event. Only the framing differs: Wi-Fi sends
it whole in one SSE `data:` line, while BLE splits it across notifications.

Over BLE, OpenFlight advertises one service with a shot notification and a
bidirectional control characteristic:

| Attribute | UUID |
|---|---|
| Shot service | `B6F633F2-E6E3-45AE-84B4-968ECCA2D9C7` |
| Shot notification | `2B28F67E-9011-41D2-98ED-562B47D7A5E4` |
| Control write + notification | `7E3B5D6C-7F10-4D4A-9C39-25E2B77F4A11` |

Each event is compact UTF-8 JSON with `schema_version: 1`. Optional
measurements are present as `null` when the active hardware could not produce
them. The version-one fields are:

```text
schema_version, event_id, timestamp, club, ball_speed_mph,
club_speed_mph, smash_factor, estimated_carry_yards,
launch_angle_vertical, launch_angle_horizontal, spin_rpm,
club_path_deg, spin_axis_deg
```

Over BLE the JSON is split into conservative 20-byte notifications. Every notification
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

Control writes and responses use the same framing. A command contains
`schema_version`, a unique `request_id`, a `type`, and a JSON `payload`. The Pi
notifies a response with the matching `request_id`, `ok`, and either `result` or
`error`. Version one supports `set_club` and
`iwr6843_orientation_calibration`.

## Delivery behavior

- Shot processing never waits for either transport, and a failure in one cannot
  affect the other, the browser UI, or session logging.
- Each connected client gets a bounded queue of eight unsent events; the oldest
  queued event is dropped if that client cannot keep up. One stalled phone
  cannot slow down another.
- Disconnecting clears that client's queue but retains the latest completed shot
  for replay on the next connection.
- The iOS app ignores a replayed event when its `event_id` is already visible.

## Security and scope

Version one intentionally has no application authentication or encryption layer
on either transport. Enable BLE only where nearby Bluetooth devices receiving
shots and issuing club or calibration commands is acceptable, and treat the
Wi-Fi API as accessible to anything on the same network — the same assumption
the browser UI already makes. Phone-assisted calibration can update and persist
TI mount tilt, so use either transport only in a trusted environment.

Add authenticated pairing before expanding the control channel to sensitive or
destructive operations.

## Troubleshooting

**The Wi-Fi transport will not connect.**

- Confirm the address with `curl -N http://<host>:8080/api/shots/stream` from a
  computer on the same network. If curl works and the app does not, the problem
  is on the phone, not the Pi.
- If `<hostname>.local` does not resolve, try the Pi's IP address; some networks
  block mDNS.
- Accept the iOS local network permission prompt. Deny it once and the app
  cannot reach the Pi until you re-enable it in Settings, Privacy & Security,
  Local Network.
- Keep the phone on the same network as the Pi; this transport does not traverse
  routers or VPNs.

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
refused the advertisement. Register the advertisement one property group at a
time to find out which part it objects to:

```bash
uv run python scripts/hardware-test/test_ble_advertise.py
```

The probe prints which layer is implicated. For the parameter-level detail,
capture the management interface while it runs:

```bash
sudo btmon -w /tmp/ble-adv.btsnoop
```

### Known bad: Raspberry Pi kernel 6.18.34+rpt-rpi-2712

On this kernel every advertisement is rejected, including one carrying no data
at all. `Add Extended Advertising Parameters (0x0054)` succeeds and reports 31
bytes available for both advertising and scan response data, and then `Add
Extended Advertising Data (0x0055)` fails with `Invalid Parameters (0x0d)` for
a zero-byte payload:

```text
@ MGMT Event: Command Complete   Add Extended Advertising Parameters (0x0054)
        Status: Success (0x00)
        Available adv data len: 31
        Available scan rsp data len: 31
@ MGMT Command:                  Add Extended Advertising Data (0x0055)
        Advertising data length: 0
        Scan response length: 0
@ MGMT Event: Command Status     Add Extended Advertising Data (0x0055)
        Status: Invalid Parameters (0x0d)
```

Nothing in userspace can shrink a zero-byte payload, so no OpenFlight or Bless
setting works around this. Boot a kernel without the regression (6.12.x is
reported to work) and rerun the probe. Until then, use the Wi-Fi transport
above: it needs no Bluetooth and delivers the identical payload.

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
uv run pytest tests/test_ble_protocol.py tests/test_ble_publisher.py \
  tests/test_shot_stream.py tests/test_phone_orientation_calibration.py \
  tests/test_control_commands.py -v

xcodebuild test \
  -project ios/OpenFlight.xcodeproj \
  -scheme OpenFlight \
  -destination "platform=iOS Simulator,id=PASTE-SIMULATOR-UUID-HERE" \
  CODE_SIGNING_ALLOWED=NO
```

List valid simulator UUIDs first with `xcrun simctl list devices available`.
