# iOS Integration — Patchfly

iOS is the **hardest platform** for code push because Apple code-signs every binary in the app bundle at install time. Unlike Android, you cannot `dlopen()` a replacement `App` executable at runtime — the kernel rejects unsigned or re-signed Mach-O files.

## Status: SDK + CLI + native updater done, engine fork needed for the actual swap

| Stage | Status | Notes |
|---|---|---|
| `lib/check` for update | ✅ works | SDK queries server (same as Android) |
| `lib/download` patch | ✅ works | Verifies SHA-256 + ed25519 signature |
| `lib/apply` to native plugin | ✅ works | Stages `.patchfly` file in caches/patches/<N>/App |
| Native updater `shorebird_init` + `shorebird_update` | ✅ works | Rust static lib, C API via bridging header |
| PatchflyAppDelegate + PatchflyFlutterViewController | ✅ works | Reads active path, calls native updater |
| Engine loads patched code | ❌ **requires engine fork** | See "Production path" |

## Architecture

### Native Plugin Files (`sdk/ios/`)

| File | Purpose | Android equivalent |
|---|---|---|
| `Classes/PatchflyPlugin.swift` | MethodChannel handler — `apply`, `verify`, `getActivePath`, `getActivePatchNumber`, `isUpdaterAvailable` | `PatchflyPlugin.kt` |
| `Classes/PatchflyAppDelegate.swift` | Calls native updater init at startup | `PatchflyApplication.kt` |
| `Classes/PatchflyFlutterViewController.swift` | Custom `FlutterViewController` that checks for patched engine | `PatchflyFlutterLoader.kt` |
| `Classes/patchfly_updater-Bridging-Header.h` | C API bridge to Rust static lib | N/A (Android uses JNI) |
| `patchfly.podspec` | CocoaPods spec | `build.gradle` |

### Native Updater (`patchfly-updater` repo)

The native updater is a **Rust static library** (`libpatchfly_updater.a`) compiled for iOS:

| Target | Architecture | Purpose |
|---|---|---|
| `aarch64-apple-ios` | arm64 | Physical devices |
| `x86_64-apple-ios` | x86_64 | Intel Mac simulators |
| `aarch64-apple-ios-sim` | arm64 | Apple Silicon simulators |

These are lipo'd into fat libraries and packaged as an **xcframework** for Xcode consumption.

**C API surface** (exposed via bridging header):

```c
void    shorebird_init(void);
int     shorebird_update(void);
char*   shorebird_active_path(void);
int     shorebird_active_patch_number(void);
void    shorebird_free_string(char* s);
```

## Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. Dart SDK: download patch from server                        │
│     → saves as .patchfly file (vs .so on Android)               │
│                                                                   │
│  2. Dart calls apply() via MethodChannel                         │
│     → Swift copies patch to caches/patches/<N>/App               │
│                                                                   │
│  3. Next cold start:                                              │
│     AppDelegate → PatchflyAppDelegate.configure()                │
│     → calls shorebird_init() + shorebird_update() via Rust       │
│                                                                   │
│  4. PatchflyFlutterViewController                                 │
│     → checks for active patched binary                           │
│     → with engine fork: loads from alternate path                │
│     → without engine fork: falls through to bundled App          │
└─────────────────────────────────────────────────────────────────┘
```

## The iOS Code Signing Challenge

Apple requires **every executable** in the app bundle to be signed with the team's provisioning profile at build time. At runtime:

- `App.framework/App` (the AOT-compiled Dart code) lives inside the signed `.app` bundle
- You **cannot** modify or replace it — the kernel validates code signatures on page faults
- You **cannot** `dlopen()` an unsigned Mach-O from the app's Documents/Caches directory

### Possible approaches

| Approach | Feasibility | Trade-off |
|---|---|---|
| **Custom Flutter Engine Fork** (recommended) | Same as Shorebird | Requires maintaining an engine fork per Flutter release |
| **Snapshot Blob Loading** | Experimental | Load Dart VM snapshot from a file instead of linked binary; requires engine changes |
| **Asset-only patching** | Works today | Only patch assets (images, JSON, fonts), not Dart code |

The **custom Flutter engine fork** is the only approach that supports full code push, and it is the same path Shorebird takes.

## Production path: engine fork

### Overview

1. Fork Flutter's engine: `https://github.com/flutter/engine`
2. Modify the `App.framework/App` loading code in `shell/platform/darwin/`
3. Build a custom Flutter SDK with this engine
4. Distribute to all developers on your team
5. Maintain it for each Flutter release

### Concrete diff example

In `shell/platform/darwin/ios/framework/Source/` (or equivalent in your engine fork), find where `App.framework` is loaded. Replace the path construction:

```objc
// BEFORE:
NSString* appFrameworkPath = [NSBundle mainBundle].executablePath;
// ... loads App.framework/App

// AFTER:
NSString* overridePath = [[NSUserDefaults standardUserDefaults] objectForKey:@"PATCHFLY_APP_PATH"];
NSString* appFrameworkPath;
if (overridePath && [[NSFileManager defaultManager] fileExistsAtPath:overridePath]) {
    appFrameworkPath = overridePath;  // use the patched file
} else {
    appFrameworkPath = [NSBundle mainBundle].executablePath;
}
```

### Wire it up in PatchflyAppDelegate

After the engine fork is in place, the SDK side becomes:

```swift
// in PatchflyAppDelegate.configure()
if let activePath = getActivePatchPath(), verifySha256(activePath) {
    // Tell the engine fork where to find the patched binary
    UserDefaults.standard.set(activePath, forKey: "PATCHFLY_APP_PATH")
} else {
    UserDefaults.standard.removeObject(forKey: "PATCHFLY_APP_PATH")
}
```

### Distribute the custom Flutter SDK

Once built, the custom Flutter SDK is distributed via a private CocoaPods spec repo or an internal mirror. Your team installs it via a custom `flutter` channel. Shorebird's CLI does this transparently.

This is a one-time investment, then ongoing maintenance per Flutter release.

## Setup steps

### 1. Build the Rust native updater for iOS targets

```bash
cd patchfly-updater

# Add iOS targets
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim

# Build for each target
cargo build --release --target aarch64-apple-ios
cargo build --release --target x86_64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

# Create fat libraries and xcframework
mkdir -p target/ios-universal/device target/ios-universal/simulator
lipo -create \
  target/aarch64-apple-ios/release/libpatchfly_updater.a \
  -output target/ios-universal/device/libpatchfly_updater.a
lipo -create \
  target/x86_64-apple-ios/release/libpatchfly_updater.a \
  target/aarch64-apple-ios-sim/release/libpatchfly_updater.a \
  -output target/ios-universal/simulator/libpatchfly_updater.a

xcodebuild -create-xcframework \
  -library target/ios-universal/device/libpatchfly_updater.a \
  -library target/ios-universal/simulator/libpatchfly_updater.a \
  -output target/ios-universal/patchfly_updater.xcframework
```

### 2. Add the xcframework to your Xcode project

- Drag `patchfly_updater.xcframework` into your Xcode project
- Ensure "Copy items if needed" is checked
- Add to the "Frameworks, Libraries, and Embedded Content" section

### 3. Update AppDelegate.swift

Replace the default Flutter setup with PatchflyAppDelegate:

```swift
import UIKit
import Flutter

@UIApplicationMain
class AppDelegate: PatchflyAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure the native updater (calls shorebird_init + shorebird_update)
        PatchflyAppDelegate.configure()
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

### 4. Use PatchflyFlutterViewController

In your `Main.storyboard` or programmatic setup, use `PatchflyFlutterViewController` instead of `FlutterViewController`:

```swift
// In SceneDelegate or storyboard
let viewController = PatchflyFlutterViewController()
// This checks for an active patched binary before falling through
// to the standard Flutter engine initialization
```

### 5. CLI setup

```bash
# Initialize iOS support
patchfly init --platform ios

# Create a patch
patchfly patch --platform ios

# Check status
patchfly doctor --platform ios
```

## Alternative: asset-only patching (no engine fork)

If you don't need code push, you can use Patchfly to deliver asset updates that work **without any engine modification**:

- **Images** — swap out PNG/JPG assets
- **JSON configuration** — feature flags, A/B test configs
- **Translation files** — updated strings
- **Fonts** — new typefaces

The plugin's download + verify + install infrastructure handles delivery and integrity checks.

```dart
// Download and apply an asset-only patch
final update = await Patchfly.instance.checkForUpdate();
if (update != null) {
    final path = await Patchfly.instance.download(update);
    await Patchfly.instance.apply(path);
    // Assets are now updated — reload UI as needed
}
```

## Diagnostic commands

```bash
# Check active patch path (on-device, via Xcode console)
po UserDefaults.standard.string(forKey: "PATCHFLY_APP_PATH")

# List staged patches
ls ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<APP-ID>/Library/Caches/patchfly/patches/

# Verify xcframework architectures
lipo -info path/to/patchfly_updater.xcframework/ios-arm64/libpatchfly_updater.a
lipo -info path/to/patchfly_updater.xcframework/ios-arm64_x86_64-simulator/libpatchfly_updater.a

# Check Rust library symbols
nm -gU path/to/patchfly_updater.xcframework/ios-arm64/libpatchfly_updater.a | grep shorebird

# Flutter doctor with iOS details
patchfly doctor --platform ios
```

## Test plan (when you have the engine fork)

1. Build app with UI title "v1" — install on device/simulator
2. Build patched version with UI title "v2" — upload as patch via CLI
3. App shows "v1" on first launch
4. Trigger check → finds patch v2
5. Download → applies → prompts restart
6. Cold restart → app shows "v2" (engine fork loaded from PATCHFLY_APP_PATH)
7. Verify crash rate via telemetry — should be zero
8. Test rollback: remove patch → restart → app shows "v1" again

## Reference: iOS app bundle structure

```
MyApp.app/
├── Info.plist
├── App                        ← AOT-compiled Dart code (target, code-signed)
├── Frameworks/
│   ├── App.framework/
│   │   └── App                ← AOT snapshot (code-signed, read-only)
│   ├── Flutter.framework/
│   │   └── Flutter            ← Flutter engine
│   └── patchfly_updater.framework/   ← Rust native updater
├── Assets.car
└── ...
```

At runtime, the Flutter engine loads `App.framework/App` from the signed bundle. The kernel validates the code signature on every page fault. Read-only at runtime.

## App Store considerations

> ⚠️ **Important**: Apple's App Store Review Guidelines (§2.5.2) prohibit downloading executable code. A custom engine fork that redirects binary loading may conflict with these rules. Shorebird operates in a gray area by arguing the "code" is interpreted data.

**Mitigations:**
- Use asset-only patching for App Store-distributed apps
- Use TestFlight for staged rollouts of code changes
- Use enterprise distribution for internal apps (no App Store restrictions)
- Monitor Apple's stance on Shorebird/code push for any policy changes
