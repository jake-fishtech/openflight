# OpenFlight iOS app

> **BLE blocker — check the Raspberry Pi kernel first:** Raspberry Pi kernel
> `6.18.34+rpt-rpi-2712` has a confirmed regression that rejects every BLE
> advertisement, including an empty one. Run `uname -r` on the Pi before
> troubleshooting the app. If it reports that version, no OpenFlight or Bless
> setting can fix BLE: use the Wi-Fi transport, or boot a working kernel such as
> 6.12.x. See the [captured failure and full diagnosis](../docs/ios-ble.md#known-bad-raspberry-pi-kernel-61834rpt-rpi-2712).

This directory contains the native SwiftUI companion app for OpenFlight. It
shows completed shots, keeps recent shot history, renders the 3D driving range,
changes the active club, and calibrates an IWR6843 mount from the iPhone's motion
sensors.

The app receives the same shot data over either:

- **Bluetooth Low Energy (BLE):** works without a shared network, but the Pi
  must start OpenFlight with `--ble`.
- **Wi-Fi:** works whenever the iPhone can reach the Pi's normal HTTP server;
  no extra server flag is required.

For protocol details and Pi-side diagnostics, see the
[iOS connection guide](../docs/ios-ble.md).

## Requirements

- A Mac with Xcode 16 or newer
- An iPhone or iPad running iOS 17 or newer for real-device testing
- An Apple ID added to Xcode; a free Personal Team is sufficient for local
  device development, while distribution requires the appropriate Apple
  Developer Program membership
- A working OpenFlight checkout on the Mac
- A Raspberry Pi running OpenFlight for end-to-end shot delivery

There are no Swift package, CocoaPods, or other third-party iOS dependencies.
Opening the checked-in Xcode project is sufficient.

## First-time setup

### 1. Clone OpenFlight and open the project

```bash
git clone https://github.com/jewbetcha/openflight.git
cd openflight
open ios/OpenFlight.xcodeproj
```

Open `OpenFlight.xcodeproj`, not the repository root. There is no generated
workspace and no package-install step.

### 2. Add your Apple account

In Xcode, open **Xcode > Settings > Accounts**, add your Apple ID, and confirm
that Xcode shows a development team.

### 3. Configure signing

The checked-in project may reference the maintainer's development team, which
will not be available to another contributor.

1. Select the blue **OpenFlight** project in Xcode's navigator.
2. Select the **OpenFlight** app target.
3. Open **Signing & Capabilities**.
4. Leave **Automatically manage signing** enabled and select your team.
5. If `org.openflight.ios` is unavailable, replace it with a unique reverse-DNS
   identifier such as `com.yourname.openflight`.
6. If you plan to run tests on a physical device, select the same team for the
   **OpenFlightTests** and **OpenFlightUITests** targets and give their bundle
   identifiers the same unique prefix.

Xcode records team and bundle-identifier changes in
`ios/OpenFlight.xcodeproj/project.pbxproj`. These are personal development
settings unless a maintainer intentionally changes the project defaults, so
inspect `git diff` and do not include your personal signing values in unrelated
commits.

### 4. Prepare a physical iPhone or iPad

1. Connect the device to the Mac by cable for the first run.
2. Unlock it and accept **Trust This Computer** if prompted.
3. Select the device in Xcode's run-destination picker.
4. If iOS asks for Developer Mode, enable it under
   **Settings > Privacy & Security > Developer Mode**, restart the device, and
   confirm the prompt.
5. Press **Run** in Xcode.

Wireless debugging can be enabled later from **Window > Devices and
Simulators** after the first trusted cable connection.

### 5. Accept the permissions the selected features need

- **Bluetooth:** required for BLE shot delivery.
- **Local Network:** required for Wi-Fi shot delivery to the Pi.
- **Motion & Fitness:** required only for phone-assisted radar tilt
  calibration.

If a permission is denied, re-enable it in the iPhone's Settings app. Deleting
and reinstalling the development build also resets its permission prompts.

## Prepare the Raspberry Pi

Run commands from the OpenFlight repository on the Pi.

### Wi-Fi

Start OpenFlight normally. The shot stream is part of the standard server:

```bash
scripts/start-kiosk.sh
```

Before debugging the app, verify the stream from another machine on the same
network:

```bash
curl -N http://raspberrypi.local:8080/api/shots/stream
```

The connection should begin with `: ping`. In the app, select **Wi-Fi** and use
`raspberrypi.local:8080`. If the Pi has a different hostname, use
`<hostname>.local:8080` or its IP address.

### Bluetooth

Install the optional server dependency once, then start with BLE enabled:

```bash
uv sync --extra ble
scripts/start-kiosk.sh --ble
```

Confirm that the Pi adapter is powered:

```bash
bluetoothctl show
```

The output should contain `Powered: yes`. In the app, select **Bluetooth**; it
scans only for the OpenFlight service and connects automatically.

## Verify the app

1. Confirm the app reaches **Connected** over the selected transport.
2. Complete a shot and confirm it appears on the dashboard.
3. Open **Driving Range** and confirm the trajectory and metrics appear.
4. Change **Club for next shot** and confirm the Pi accepts the change.
5. If using an IWR6843, run the phone calibration once on a physical device.

The Pi replays its most recent completed shot when the app connects. A new
installation therefore does not need to wait for another shot if one has
already been recorded during the current server run.

## Run automated tests

### In Xcode

Choose a simulator or physical device and use **Product > Test** (`Command-U`).
Unit tests work in the simulator. BLE delivery and motion calibration still
require a physical iPhone and Pi for meaningful end-to-end validation.

### From Terminal

Do not copy a simulator name from another developer's command. List the devices
installed on the current Mac first:

```bash
xcrun simctl list devices available
```

Then paste an available simulator's UUID into the destination:

```bash
xcodebuild test \
  -project ios/OpenFlight.xcodeproj \
  -scheme OpenFlight \
  -destination "platform=iOS Simulator,id=PASTE-SIMULATOR-UUID-HERE" \
  CODE_SIGNING_ALLOWED=NO
```

To run only the unit-test target:

```bash
xcodebuild test \
  -project ios/OpenFlight.xcodeproj \
  -scheme OpenFlight \
  -destination "platform=iOS Simulator,id=PASTE-SIMULATOR-UUID-HERE" \
  -only-testing:OpenFlightTests \
  CODE_SIGNING_ALLOWED=NO
```

## Issues encountered and their workarounds

### Signing says the development team is unavailable

**Symptoms:** `No Account for Team`, a provisioning-profile error, or Xcode
cannot sign `OpenFlight`.

**Cause:** the checked-in team belongs to another developer, or the default
bundle identifier is already registered.

**Fix:** add your Apple ID, select your team under **Signing & Capabilities**,
and use unique bundle identifiers. Apply the same team to the app, unit-test,
and UI-test targets when those targets also report signing errors.

### A physical device cannot launch the development build

**Symptoms:** the destination is unavailable, the device says the developer is
untrusted, or Xcode says Developer Mode is disabled.

**Fix:** unlock and trust the device, enable Developer Mode, restart when iOS
requests it, and retry from Xcode. Confirm that the device runs iOS 17 or newer.

### `Unable to find a device matching the provided destination specifier`

**Cause:** simulator names are not portable. For example, a command naming
`iPhone 16` fails on a Mac that only has an `iPhone 17 Pro` simulator.

**Fix:** run `xcrun simctl list devices available` and use an installed device's
UUID. If no devices are listed, install an iOS simulator runtime from Xcode's
platform settings.

### `CoreSimulatorService connection became invalid`

**Fix:** run the build from a normal logged-in macOS Terminal session, launch
Xcode and Simulator once, and confirm the command-line tools point at the full
Xcode installation:

```bash
xcode-select -p
xcodebuild -version
```

The selected developer directory should normally be
`/Applications/Xcode.app/Contents/Developer`. If the service remains stale,
quit Xcode and Simulator, run `xcrun simctl shutdown all`, reopen Xcode, and
retry. Restricted or sandboxed automation may need explicit simulator access.

### Tests log `Connection refused` for `127.0.0.1:8080`

The unit-test host can launch the app without an OpenFlight server running. The
resulting network log is expected and does not fail otherwise-passing unit
tests. End-to-end Wi-Fi tests require a reachable Pi. UI tests pass the
`--ui-testing` argument to suppress the automatic connection.

### Xcode warns that App Intents metadata extraction was skipped

The app does not depend on `AppIntents.framework`. This build warning is
harmless and does not indicate a failed test or missing dependency.

### Bluetooth does not work in Simulator

CoreBluetooth in Simulator is not a useful end-to-end test of the Pi's BLE GATT
server. Use Simulator for unit and UI tests, and use a physical iPhone plus the
Pi for BLE acceptance testing.

### The Bluetooth permission was denied

Open **Settings > Privacy & Security > Bluetooth** and enable OpenFlight. If it
does not appear, remove and reinstall the development build to trigger the
prompt again.

### The app stays on `Looking for OpenFlight` over Bluetooth

1. Confirm the Pi was started with `scripts/start-kiosk.sh --ble`.
2. Confirm `bluetoothctl show` reports `Powered: yes`.
3. Keep the app in the foreground for the initial scan.
4. Restart OpenFlight after changing Bluetooth configuration.
5. Check the OpenFlight terminal for `[BLE]` warnings.

If the app connects but phone controls are unavailable, update the Pi to a
version that supports the BLE control characteristic and restart OpenFlight.

### The Pi says Bluetooth or Bless is unavailable

Install the optional dependency and confirm BlueZ is running:

```bash
uv sync --extra ble
systemctl status bluetooth
```

The user running OpenFlight must also be able to access the system D-Bus and
Bluetooth adapter.

### The Pi logs `Failed to register advertisement: Invalid Parameters`

Run the repository's advertising probe and inspect the BlueZ log:

```bash
uv run python scripts/hardware-test/test_ble_advertise.py
journalctl -u bluetooth -n 20 --no-pager
```

Raspberry Pi kernel `6.18.34+rpt-rpi-2712` has a confirmed regression that
rejects even an empty advertisement. There is no OpenFlight or Bless
configuration workaround. Boot a known-working kernel such as 6.12.x, or use
the Wi-Fi transport until the kernel issue is resolved. The full evidence and
`btmon` procedure are in the [connection guide](../docs/ios-ble.md#known-bad-raspberry-pi-kernel-61834rpt-rpi-2712).

### Wi-Fi does not connect

1. Run `curl -N http://<host>:8080/api/shots/stream` from another machine on
   the phone's network.
2. If `<hostname>.local` fails, use the Pi's IP address; some networks block
   mDNS.
3. Put the phone and Pi on the same network and temporarily disable VPNs or
   client-isolation features that prevent local-device traffic.
4. Re-enable OpenFlight under **Settings > Privacy & Security > Local Network**.
5. Leave `OpenFlight-Info.plist` in the target; it contains the local-network
   usage description and permits plain HTTP for local networking.

### The app connects but a shot does not appear

- Confirm the browser UI received a completed shot. The app receives completed
  events, not every intermediate radar reading.
- Check the server terminal for `[BLE]` warnings or stream errors.
- Tap **Retry** in the app.
- For Wi-Fi, keep only necessary stream clients open; the server returns `503`
  after eight simultaneous clients.

### Motion calibration is unavailable or unstable

- Use a physical iPhone; Simulator has no meaningful motion-sensor input.
- Grant Motion & Fitness permission.
- Remove the phone case, avoid the camera bump, and hold the phone still against
  the reference surface for the full sample window.
- Keep left/right roll within 3 degrees before applying calibration.

## Where to look next

- [iOS transport, protocol, security, and Pi troubleshooting](../docs/ios-ble.md)
- [Raspberry Pi setup](../docs/raspberry-pi-setup.md)
- [IWR6843 operator guide](../docs/iwr6843/README.md)
- [Root project README](../README.md)
