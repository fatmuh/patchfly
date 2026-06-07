# SDK Usage

## Installation

Add to your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  patchfly:
    path: /path/to/patchfly/sdk
    # or, once published:
    # patchfly: ^0.1.0
```

## Initialization

```dart
import 'package:patchfly/patchfly.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Patchfly.init(
    serverUrl: 'https://updates.example.com',
    sdkKey: 'pfk_...',  // from `patchfly apps create`
    channel: 'stable',  // or 'beta', 'internal', 'alpha'
  );
  
  runApp(const MyApp());
}
```

## Triggering updates

### Check on app start

```dart
void main() async {
  // ... init ...
  
  final update = await Patchfly.instance.checkForUpdate();
  if (update != null) {
    if (await _showUpdateDialog(update)) {
      final path = await Patchfly.instance.download(update);
      await Patchfly.instance.apply(path);
    }
  }
  
  runApp(const MyApp());
}
```

### Check on a button press

```dart
ElevatedButton(
  onPressed: () async {
    final update = await Patchfly.instance.checkForUpdate();
    if (update == null) {
      showSnack('No update available');
      return;
    }
    final path = await Patchfly.instance.download(update);
    await Patchfly.instance.apply(path);
  },
  child: Text('Check for update'),
)
```

### Check in the background

```dart
// On app start, after init
Timer(const Duration(seconds: 5), () async {
  try {
    final update = await Patchfly.instance.checkForUpdate();
    if (update != null) {
      // Show a banner or notification
      showUpdateBanner(update);
    }
  } catch (e) {
    // Network error, etc. — log and move on.
  }
});
```

## Channels

Use channels for staged rollouts:
- `stable` — production users
- `beta` — opt-in beta testers
- `internal` — your team only (use a build flavor)
- `alpha` — close testers

In your app:
```dart
const channel = String.fromEnvironment('PATCHFLY_CHANNEL', defaultValue: 'stable');
await Patchfly.init(..., channel: channel);
```

In your CI:
```bash
flutter build apk --dart-define=PATCHFLY_CHANNEL=beta
```

## Error handling

```dart
try {
  final update = await Patchfly.instance.checkForUpdate();
  if (update != null) {
    final path = await Patchfly.instance.download(update);
    await Patchfly.instance.apply(path);
  }
} on PatchflyNetworkException catch (e) {
  // Server unreachable, no internet, etc.
  // → Log and continue with the bundled code.
} on PatchflySignatureException catch (e) {
  // Patch signature invalid → DON'T apply. This is a security issue.
  // → Log to your error tracker.
} on PatchflyApplyException catch (e) {
  // Platform code couldn't apply the patch.
  // → Log. The bundled code keeps running.
} on PatchflyException catch (e) {
  // Any other SDK error.
  // → Log and continue.
}
```

## Configuration reference

| Option | Type | Default | Notes |
|---|---|---|---|
| `serverUrl` | String | required | Where the Patchfly server is hosted |
| `sdkKey` | String | required | Per-app secret, generated on `apps create` |
| `channel` | String | `'stable'` | Which release channel to query |
| `verbose` | bool | `false` | Log every API call |

## Local patch path

If the SDK has previously downloaded a patch, the path is available:

```dart
final path = Patchfly.instance.localPatchPath;
```

The app's host code reads this on next launch to decide which binary to load.
On Android, `MainActivity` uses it to decide which `libapp.so` to `dlopen()`.
On iOS, `PatchflyAppDelegate` and `PatchflyFlutterViewController` use it to
determine the active patch path. You don't usually need to touch this directly.

## Platform-specific setup

### Android

The Android native plugin is automatically registered via Flutter's plugin system.
The key integration points are:

- **`PatchflyApplication.kt`** — Subclass this in your app's `Application` class
  to handle patch staging and verification on cold start.
- **`MainActivity`** — No changes needed if using the default setup.

For full details, see [Android Integration](ANDROID_INTEGRATION.md).

### iOS

iOS requires manual setup in your Xcode project:

1. **AppDelegate.swift** — Replace the default Flutter `AppDelegate` with
   `PatchflyAppDelegate` and call `PatchflyAppDelegate.configure()` in
   `didFinishLaunchingWithOptions`.
2. **FlutterViewController** — Use `PatchflyFlutterViewController` instead of
   the standard `FlutterViewController` in your storyboard or programmatic setup.
3. **Native updater xcframework** — Build and link the Rust `patchfly_updater`
   xcframework (see [iOS Integration](IOS_INTEGRATION.md) for build steps).

For full details, see [iOS Integration](IOS_INTEGRATION.md).

## Custom server URL (testing)

For local development with a tunnel (ngrok, Cloudflare Tunnel):

```dart
await Patchfly.init(
  serverUrl: 'https://abc123.ngrok.io',
  sdkKey: '...',
);
```

The server's public key is fetched from `<serverUrl>/api/v1/sdk/public-key`
on every `init()`. The SDK verifies every patch against this key.
