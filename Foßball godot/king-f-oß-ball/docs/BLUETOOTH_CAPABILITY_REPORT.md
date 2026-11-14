# Bluetooth capability report (P6 spike)

Date: 2026-11-14. Scope: determine whether the phone-as-controller path can be
delivered over Bluetooth in addition to the Wi-Fi/KING CONTROLLER path (P5).

## Finding: Godot 4.7 has no built-in Bluetooth API

- `ClassDB` exposes no `Bluetooth*`, `BluetoothServer`, or `BluetoothSocket`
  class in 4.7.2 (verified by enumerating classes; no `bluetooth`/`bt` symbol).
- There is no Bluetooth module in the engine's default build and no autoload.
- `OS` and `DisplayServer` expose nothing Bluetooth-related.
- Conclusion: **any Bluetooth support must come from a platform-specific native
  plugin** (GDExtension on Android via JNI to `android.bluetooth.*`, and on
  Windows via WinRT `Windows.Devices.Bluetooth`). There is no cross-platform
  abstraction to reuse.

## What a real implementation would require (not done here)

Android (the only platform where "phone as gamepad over BT" is realistic):
1. A GDExtension (C++/Kotlin) wrapping `BluetoothAdapter`, device discovery,
   `BluetoothSocket` RFCOMM/SPP or BLE GATT, pairing flow, and a small binary
   framing identical to `KingControllerProtocol`.
2. Manifest permissions: `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_CONNECT`,
   `BLUETOOTH_SCAN`, `ACCESS_FINE_LOCATION` (pre-Android-12), plus runtime
   permission requests.
3. A second controller page is NOT needed (BT is device-to-device, no browser),
   but a native companion app or a native plugin on the phone side is required.
4. Testing on a real Android device with two BT radios; no emulator coverage for
   real radio behaviour.

Windows host side: WinRT `Windows.Devices.Bluetooth` + RFCOMM, plus a pairing UI.
Effort estimate: 2-4 weeks of native work per platform, plus device testing.

## What is NOT claimed
- No Bluetooth code ships in this repository.
- No "Bluetooth controller" UI, button, or setting exists.
- No simulated or fake Bluetooth path is provided. The only phone-controller
  path that is implemented and tested is KING CONTROLLER over local Wi-Fi (P5).

## Recommendation
Keep **Wi-Fi (KING CONTROLLER) as the supported phone-controller path** for v1.
Revisit Bluetooth only if a concrete user need and device-test budget exist; at
that point, build the Android GDExtension first (highest value) and reuse the
`KingControllerProtocol` framing (it is transport-agnostic).

## Cross-references
- `docs/KING_CONTROLLER_ARCHITECTURE.md` (P5, implemented + tested)
- `docs/CROSS_PLATFORM_STRATEGY.md` (platform matrix, P6 row)
- `docs/audits/GAMEPLAY_AND_CROSS_PLATFORM_AUDIT.md` §7 (P6 scope)