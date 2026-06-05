# Android Integration — Patchfly

This is the **hardest** part of the system. The Flutter engine loads `libapp.so` from the app's native library directory (set by Android at install time, read-only), and we want to swap it with a downloaded patch.

## Status: SDK does the easy parts, engine fork needed for the actual swap

| Stage | Status | Notes |
|---|---|---|
| `lib/check` for update | ✅ works | SDK queries server |
| `lib/download` patch | ✅ works | Verifies SHA-256 + ed25519 signature |
| `lib/apply` to native plugin | ✅ works | Stages `active.so` + sidecar, restarts process |
| `lib/dlopen()` patched libapp.so | ⚠️ documented attempt | See "What doesn't work" below |
| Engine uses patched code | ❌ **requires engine fork** | See "Production path" |

## What doesn't work, and why

`PatchflyApplication.attachBaseContext` runs BEFORE the Flutter engine starts. It tries to pre-load the patched library with `System.load(absolutePath)` (a `dlopen` underneath). On paper, when Flutter's engine later calls `dlopen("libapp.so")`, the Bionic linker should find the cached one.

**In practice this fails on modern Android (5+)** because:

- Flutter's engine uses the **full path** for `dlopen`:
  `dlopen(applicationContext.getNativeLibraryDir() + "/libapp.so", RTLD_NOW)`
- Bionic's dlopen cache uses the full path as the lookup key (with SONAME fallback)
- Pre-loading from `/data/data/.../files/patchfly/patches/libapp.so` registers a different cache key
- Flutter's `dlopen` misses the cache, finds the bundled `libapp.so` in `nativeLibraryDir`, loads it
- The patched library IS mapped into the process address space (visible in `/proc/self/maps`) but the Dart VM binds to the bundled one

**Empirically verified on Android 14 (Redmi Note 8 Pro, Flutter 3.44):**
- `System.load(patched)` succeeds, logs show it
- Restart happens
- App shows BUNDLED UI, not patched UI
- `dlopen` cache miss confirmed via cache behavior

## What `PatchflyApplication` still does

Even though the libapp.so swap doesn't work, the class is still useful:

1. **Staging** — verifies the patch's SHA-256 against a sidecar file, deletes the patch if verification fails
2. **Safety net** — the catch block on `System.load` failure deletes the patch and falls through to the bundled library (no crash)
3. **Hook point** — if you DO maintain an engine fork, you can subclass `PatchflyApplication` and add your own load logic here
4. **Idempotency** — `active.so` is loaded from the staged position on every cold start; safe to call repeatedly

The plugin's full flow is:
- `apply(path, sha256)` → copies to `active.so` + writes sidecar
- Restart the process
- `PatchflyApplication.attachBaseContext` reads `active.so`, verifies, attempts to load
- Flutter's engine then does its own load — with an unmodified engine, this loads the bundled copy

## Production path: engine fork (the only real solution)

This is what Shorebird does. It is non-trivial.

### Overview

1. Fork Flutter's engine: `https://github.com/flutter/engine` (or Shorebird's `https://github.com/shorebirdtech/flutter`)
2. Modify the `libapp.so` loading code in `shell/platform/android/`
3. Build a custom Flutter SDK with this engine
4. Distribute to all developers on your team
5. Maintain it for each Flutter release

### Concrete diff example

In `shell/platform/android/library_loader.cc` (or the equivalent in the engine fork you choose), find the function that loads `libapp.so`. Replace the path construction:

```cpp
// BEFORE:
std::string libapp_path = application_context->GetNativeLibraryDir() + "/libapp.so";
return reinterpret_cast<jlong>(::dlopen(libapp_path.c_str(), RTLD_NOW));

// AFTER:
const char* override_path = getenv("PATCHFLY_LIBAPP_PATH");
std::string libapp_path;
if (override_path != nullptr && access(override_path, R_OK) == 0) {
  libapp_path = override_path;  // use the patched file
} else {
  libapp_path = application_context->GetNativeLibraryDir() + "/libapp.so";
}
return reinterpret_cast<jlong>(::dlopen(libapp_path.c_str(), RTLD_NOW));
```

### Wire it up in PatchflyApplication

After the engine fork is in place, the SDK side becomes:

```kotlin
// in tryLoadPatchedLibapp(ctx:)
if (active.exists() && verifySha256(active, expectedSha)) {
    // Set the env var the engine fork reads
    System.setenv("PATCHFLY_LIBAPP_PATH", active.absolutePath)
    // Optional: pre-load for early binding (helps libflutter.so's DT_NEEDED)
    System.load(active.absolutePath)
}
```

### Distribute the custom Flutter SDK

Once built, the custom Flutter goes into a private Maven / Cocoapods / pub.dev mirror. Your team installs it via `flutter` channel. Shorebird's "shorebird" CLI does this transparently.

This is a one-time investment, then ongoing maintenance per Flutter release.

## Alternative: just ship the plugin and accept the limitation

If your app's update mechanism doesn't strictly require code swap (e.g., you ship new features via remote config, dynamic widgets, etc.), you can use Patchfly to deliver:
- **Asset bundles** (images, translations, JSON config) — works without engine fork
- **Native lib updates** (e.g., separate .so files for your own native code) — works without engine fork, as long as the entry point class is your own

The plugin's download + verify + install infrastructure is useful for these cases.

## Diagnostic commands

```bash
# Verify the patched file was loaded into the process
adb shell run-as com.your.app cat /proc/self/maps | grep libapp.so
# Should show TWO mappings: one in /data/data/.../files/ (our pre-load) and
# one in /data/app-lib/.../lib/arm64/ (Flutter's load)

# Check what's actually in the dlopen cache
adb shell lsof -p $(adb shell pidof com.your.app) | grep libapp.so
```

## Test plan when you have the engine fork

1. Bundle libapp.so A (with UI title "v1") in your app
2. Build libapp.so B (with UI title "v2") and upload as patch
3. Install app on device — shows "v1"
4. Tap Check → finds patch v2
5. Tap Download → 3.7 MB downloaded
6. Tap Apply → process restarts
7. App now shows "v2" — engine fork's loader used PATCHFLY_LIBAPP_PATH
8. Crash rate via telemetry — ideally zero. If non-zero, the patch is corrupt or engine-version-mismatched

## iOS

Not possible. App Store rules prohibit downloading and executing code outside the app bundle. There is no technical workaround for AOT-compiled Flutter on iOS.

For iOS:
- Use TestFlight for staged rollouts
- Ship a new build for hot-fixes (1-2 day review)
- Use remote config for runtime feature flags

## Reference: APK structure

```
myapp.apk
├── AndroidManifest.xml
├── classes.dex
├── lib/
│   ├── arm64-v8a/
│   │   ├── libapp.so            ← AOT-compiled Dart code (target)
│   │   ├── libflutter.so        ← Flutter engine
│   │   └── libpatchfly.so       ← your plugin (if you have native code)
│   └── armeabi-v7a/
│       └── ...
└── ...
```

At install time, Android extracts these to `/data/app/<package>-<random>/lib/<abi>/`. At runtime, `dlopen("libapp.so")` resolves to that location. Read-only at runtime.
