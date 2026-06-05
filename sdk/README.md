# Patchfly SDK

Flutter package that adds OTA update capability to your app.

## Install

```yaml
# pubspec.yaml
dependencies:
  patchfly:
    path: ../patchfly/sdk
    # or once published:
    # patchfly: ^0.1.0
```

## Usage

```dart
import 'package:patchfly/patchfly.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Patchfly.init(
    serverUrl: 'https://updates.example.com',
    sdkKey: 'pfk_...',
    channel: 'stable',
  );
  
  // Optional: check on startup
  final update = await Patchfly.instance.checkForUpdate();
  if (update != null) {
    final path = await Patchfly.instance.download(update);
    await Patchfly.instance.apply(path);
  }
  
  runApp(const MyApp());
}
```

## Android integration

**The SDK is only half the story.** Your app's `MainActivity` must be
modified to `dlopen()` the downloaded `libapp.so` before starting
Flutter.

See [`docs/ANDROID_INTEGRATION.md`](../docs/ANDROID_INTEGRATION.md) for
the full guide.

## What the SDK does

1. `init()` — fetches the server's ed25519 public key for signature
   verification
2. `checkForUpdate()` — POSTs to `/sdk/check` with device id, app
   version, channel
3. `download(update)` — GETs the patch, verifies sha256 + ed25519
   signature, saves to app's private storage
4. `apply(path)` — MethodChannel call to Android side, which restarts
   the app with the new `libapp.so` loaded

## Error handling

```dart
try {
  final update = await Patchfly.instance.checkForUpdate();
  if (update != null) {
    final path = await Patchfly.instance.download(update);
    await Patchfly.instance.apply(path);
  }
} on PatchflySignatureException catch (e) {
  // SECURITY: patch is tampered or from wrong server. Do NOT apply.
  // Log to your error tracker; bundled code keeps running.
} on PatchflyNetworkException catch (e) {
  // No internet, server down. Continue with bundled code.
} on PatchflyApplyException catch (e) {
  // Platform-side apply failed. Continue with bundled code.
}
```

## Storage

Downloaded patches are stored in:
- Android: `getApplicationSupportDirectory()/patchfly/patches/`

The most recently downloaded path is also saved in
`SharedPreferences` under the key `patchfly_local_patch_path`. Your
`MainActivity` reads this on next launch to know which `libapp.so`
to load.

## Telemetry

The SDK automatically reports these events to the server:
- `check` — every `checkForUpdate()` call
- `download` — successful patch download
- `apply` — successful `apply()` call (best-effort; only sent if app
  gets a chance to run the next tick)

Errors during `apply()` should be reported by your app code (the SDK
doesn't catch platform exceptions).

## See also

- [`docs/SDK_USAGE.md`](../docs/SDK_USAGE.md) — detailed usage
- [`docs/ANDROID_INTEGRATION.md`](../docs/ANDROID_INTEGRATION.md) —
  the `MainActivity` setup
- [`example/`](example/) — full example app
