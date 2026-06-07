//
//  PatchflyAppDelegate.swift
//  patchfly
//
//  Equivalent to Android's PatchflyApplication.kt
//
//  This class provides helper methods that should be called from
//  the app's AppDelegate to initialize the native updater early
//  in the launch cycle (before Flutter engine starts).
//
//  Usage:
//    1. Import patchfly in your AppDelegate.swift
//    2. Call PatchflyAppDelegate.configure() in application(_:didFinishLaunchingWithOptions:)
//       BEFORE the GeneratedPluginRegistrant.call(with: self) line
//

import UIKit
import Flutter

public class PatchflyAppDelegate: NSObject, FlutterApplicationDelegate {

    /// Initialize the Patchfly native updater.
    ///
    /// This should be called early in `application(_:didFinishLaunchingWithOptions:)`,
    /// before Flutter engine initialization.
    ///
    /// Flow:
    ///   1. Read app version from Bundle.main
    ///   2. Get caches directory for patch storage
    ///   3. Get bundle path (contains Frameworks/App.framework)
    ///   4. Call shorebird_init() with these paths
    ///   5. Call shorebird_update() to apply any staged patches
    ///
    /// All failures are caught and logged — the app must always start
    /// even if the updater fails.
    public static func configure() {
        NSLog("[Patchfly] Configuring native updater...")

        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            NSLog("[Patchfly] Cannot locate caches directory — skipping updater")
            return
        }

        let bundlePath = Bundle.main.bundlePath
        let version = readVersionString()

        NSLog("[Patchfly] Init: version=\(version), cache=\(cachesDir.path), bundle=\(bundlePath)")

        let rc = NativeUpdaterBridge.shared.initialize(
            version: version,
            cacheDir: cachesDir.path,
            libappDir: bundlePath
        )

        if rc != 0 {
            NSLog("[Patchfly] Native updater init failed (rc=\(rc)) — using bundled engine")
            return
        }

        // Apply any staged patches
        let updateRc = NativeUpdaterBridge.shared.update()
        if updateRc != 0 {
            NSLog("[Patchfly] shorebird_update failed (rc=\(updateRc)) — using bundled engine")
        }

        // Log active state
        let activePath = NativeUpdaterBridge.shared.activePath()
        let activePatch = NativeUpdaterBridge.shared.activePatchNumber()
        NSLog("[Patchfly] Ready: activePath=\(activePath ?? "nil"), activePatch=\(activePatch ?? "nil")")
    }

    /// Read version string in "<version>+<build>" format
    /// matching the Dart side's PackageInfo.fromPlatform()
    private static func readVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version)+\(build)"
    }
}
