//
//  PatchflyPlugin.swift
//  patchfly
//
//  iOS native plugin for Patchfly — OTA updates for Flutter apps.
//
//  Equivalent to sdk/android/src/.../PatchflyPlugin.kt on Android.
//
//  Flow:
//    1. Dart SDK downloads a patch from server → saves to app support dir
//    2. Dart calls apply() via MethodChannel → we stage the patch
//    3. On next cold start, AppDelegate runs native updater (libpatchfly_updater)
//    4. Native updater applies patch, returns path to patched App.framework/App
//    5. Custom FlutterViewController loads the patched binary
//

import Flutter
import UIKit

/// Method channel name — must match the Dart side:
/// `const channel = MethodChannel('patchfly/apply');`
private let CHANNEL = "patchfly/apply"

public class PatchflyPlugin: NSObject, FlutterPlugin {

    // MARK: - FlutterPlugin

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: registrar.messenger())
        let instance = PatchflyPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "apply":
            handleApply(call, result: result)
        case "verify":
            handleVerify(call, result: result)
        case "getActivePath":
            handleGetActivePath(result: result)
        case "getActivePatchNumber":
            handleGetActivePatchNumber(result: result)
        case "isUpdaterAvailable":
            result(isUpdaterLoaded())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Apply

    /// Stage a downloaded patch for the next app launch.
    ///
    /// Native updater cache layout on iOS:
    ///   <cacheDir>/patches/<patchNumber>/App        (full file)
    ///   <cacheDir>/patches/<patchNumber>/App.sha256  (sidecar)
    ///
    /// On next launch, AppDelegate.initNativeUpdater() calls
    /// shorebird_update() which finds and applies the patch.
    private func handleApply(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let patchPath = args["path"] as? String,
              let patchNumber = args["patchNumber"] as? Int else {
            result(FlutterError(code: "ARG_MISSING", message: "path and patchNumber are required", details: nil))
            return
        }

        let expectedSha256 = args["sha256"] as? String

        guard let cachesDir = getCachesDirectory() else {
            result(FlutterError(code: "NO_CACHES", message: "Cannot locate caches directory", details: nil))
            return
        }

        let srcURL = URL(fileURLWithPath: patchPath)
        let patchDirURL = cachesDir.appendingPathComponent("patches/\(patchNumber)")

        // Create patch directory
        do {
            try FileManager.default.createDirectory(at: patchDirURL, withIntermediateDirectories: true)
        } catch {
            result(FlutterError(code: "MKDIR_FAILED", message: error.localizedDescription, details: nil))
            return
        }

        // Copy patch file to <patchDir>/App
        let dstURL = patchDirURL.appendingPathComponent("App")
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
        } catch {
            result(FlutterError(code: "COPY_FAILED", message: error.localizedDescription, details: nil))
            return
        }

        // Write SHA256 sidecar
        if let sha = expectedSha256 {
            let sidecarURL = patchDirURL.appendingPathComponent("App.sha256")
            try? sha.write(to: sidecarURL, atomically: true, encoding: .utf8)
        }

        // Write active patch number marker file (for Dart side to read on next launch)
        let markerURL = getAppSupportDirectory()?.appendingPathComponent("patchfly/active_patch_number")
        if let markerURL = markerURL {
            try? FileManager.default.createDirectory(
                at: markerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? "\(patchNumber)".write(to: markerURL, atomically: true, encoding: .utf8)
        }

        // Write to UserDefaults for FlutterSharedPreferences compatibility
        let prefsKey = "flutter.patchfly_active_patch_number"
        UserDefaults.standard.set(patchNumber, forKey: prefsKey)
        UserDefaults.standard.synchronize()

        NSLog("[Patchfly] Patch staged for next launch: \(dstURL.path) (patch #\(patchNumber))")

        result([
            "applied": true,
            "path": dstURL.path,
            "patchNumber": patchNumber
        ])

        // Schedule process restart (equivalent to Android's Process.killProcess)
        // On iOS we can't kill the process cleanly, so we just schedule a restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.restartApp()
        }
    }

    // MARK: - Verify

    private func handleVerify(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "ARG_MISSING", message: "path is required", details: nil))
            return
        }
        let exists = FileManager.default.fileExists(atPath: path)
        result(["exists": exists, "path": path])
    }

    // MARK: - Get Active Path

    private func handleGetActivePath(result: @escaping FlutterResult) {
        // Try native updater first (libpatchfly_updater static lib)
        if let path = NativeUpdaterBridge.shared.activePath() {
            result(path)
            return
        }
        // Fallback: read from UserDefaults
        if let path = UserDefaults.standard.string(forKey: "patchfly_active_patch_path") {
            result(path)
            return
        }
        result(nil)
    }

    // MARK: - Get Active Patch Number

    private func handleGetActivePatchNumber(result: @escaping FlutterResult) {
        // Try native updater first
        if let num = NativeUpdaterBridge.shared.activePatchNumber() {
            result(num)
            return
        }
        // Fallback: UserDefaults (written by FlutterSharedPreferences)
        let num = UserDefaults.standard.integer(forKey: "flutter.patchfly_active_patch_number")
        if num > 0 {
            result("\(num)")
            return
        }
        result(nil)
    }

    // MARK: - Helpers

    private func isUpdaterLoaded() -> Bool {
        return NativeUpdaterBridge.shared.isAvailable
    }

    private func getCachesDirectory() -> URL? {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private func getAppSupportDirectory() -> URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// Restart the app by re-launching from the main storyboard.
    /// On iOS there's no equivalent of Android's Process.killProcess,
    /// so we use a UIWindowScene trick to restart the root view controller.
    private func restartApp() {
        NSLog("[Patchfly] Restarting app to apply patch...")
        // Post a notification that the AppDelegate can observe
        // to restart the FlutterViewController
        NotificationCenter.default.post(name: .PatchflyRestartRequired, object: nil)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let PatchflyRestartRequired = Notification.Name("PatchflyRestartRequired")
}

// MARK: - Native Updater Bridge
//
// This bridges to the Rust static library (libpatchfly_updater.a)
// built from patchfly-updater repo. The C API:
//   int shorebird_init(const char*, const char*, const char*);
//   int shorebird_update();
//   const char* shorebird_active_path();
//   const char* shorebird_active_patch_number();
//   void shorebird_free_string(char*);

class NativeUpdaterBridge {

    static let shared = NativeUpdaterBridge()

    private(set) var isAvailable = false
    private var initialized = false

    private init() {
        // Check if the native library is linked
        // The static lib is always linked when included in the project,
        // so we just try to call init and see if it succeeds.
        isAvailable = true
    }

    /// Initialize the native updater with app parameters.
    /// Called from AppDelegate early in the launch cycle.
    @discardableResult
    func initialize(version: String, cacheDir: String, libappDir: String) -> Int32 {
        guard isAvailable else { return -1 }

        let rc = version.withCString { v in
            cacheDir.withCString { c in
                libappDir.withCString { l in
                    shorebird_init(v, c, l)
                }
            }
        }

        if rc == 0 {
            initialized = true
            NSLog("[Patchfly] Native updater initialized: version=\(version)")
        } else {
            NSLog("[Patchfly] Native updater init failed: rc=\(rc)")
        }
        return rc
    }

    /// Apply any pending patches in the cache directory.
    @discardableResult
    func update() -> Int32 {
        guard isAvailable, initialized else { return -1 }
        let rc = shorebird_update()
        if rc != 0 {
            NSLog("[Patchfly] Native updater update failed: rc=\(rc)")
        }
        return rc
    }

    /// Get the path to the active (patched) engine binary.
    func activePath() -> String? {
        guard isAvailable, initialized else { return nil }
        guard let ptr = shorebird_active_path() else { return nil }
        defer { shorebird_free_string(UnsafeMutablePointer(mutating: ptr)) }
        return String(cString: ptr)
    }

    /// Get the active patch number as a string.
    func activePatchNumber() -> String? {
        guard isAvailable, initialized else { return nil }
        guard let ptr = shorebird_active_patch_number() else { return nil }
        defer { shorebird_free_string(UnsafeMutablePointer(mutating: ptr)) }
        return String(cString: ptr)
    }
}
