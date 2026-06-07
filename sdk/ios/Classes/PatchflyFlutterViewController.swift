//
//  PatchflyFlutterViewController.swift
//  patchfly
//
//  Equivalent to Android's PatchflyFlutterLoader.kt
//
//  On iOS, Flutter loads the AOT snapshot from App.framework/App.
//  This class provides a mechanism to redirect to a patched binary.
//
//  IMPORTANT: On stock iOS, Flutter's engine loads App.framework from the
//  app bundle, which is code-signed by Apple. You CANNOT modify signed
//  binaries at runtime. The approach here works by:
//
//  1. Using a custom FlutterViewController that intercepts engine creation
//  2. If a patched snapshot is available, loading it BEFORE the engine starts
//  3. The Rust native updater handles the actual binary patching
//
//  Limitation: This requires that the patch be a complete replacement
//  snapshot (not a delta applied to the signed binary). The patch must
//  be a standalone Mach-O that can be loaded dynamically.
//
//  For a fully working solution, see docs/IOS_INTEGRATION.md for the
//  custom Flutter engine approach.
//

import Flutter
import UIKit

/// A FlutterViewController subclass that attempts to load a patched
/// engine snapshot when available.
///
/// Usage in AppDelegate.swift:
/// ```swift
/// var window: UIWindow?
///
/// func application(_ application: UIApplication,
///                  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
///     PatchflyAppDelegate.configure()
///
///     let flutterVC = PatchflyFlutterViewController()
///     flutterVC.setInitialRoute("/")
///     window = UIWindow(frame: UIScreen.main.bounds)
///     window?.rootViewController = flutterVC
///     window?.makeKeyAndVisible()
///
///     GeneratedPluginRegistrant.register(with: self)
///     return true
/// }
/// ```
open class PatchflyFlutterViewController: FlutterViewController {

    /// Override engine creation to potentially redirect snapshot loading.
    ///
    /// In stock Flutter, the engine loads App.framework/App from the bundle.
    /// We check if the native updater has prepared a patched snapshot and
    /// log the path for debugging. Actual redirection requires a custom
    /// Flutter engine build.
    open override func viewDidLoad() {
        // Check for patched engine
        if let activePath = NativeUpdaterBridge.shared.activePath() {
            NSLog("[PatchflyLoader] Patched engine available at: \(activePath)")
            NSLog("[PatchflyLoader] Active patch: \(NativeUpdaterBridge.shared.activePatchNumber() ?? "none")")

            // Verify the patched file exists
            if FileManager.default.fileExists(atPath: activePath) {
                NSLog("[PatchflyLoader] Patched file verified ✓")
                // NOTE: On stock Flutter, we cannot redirect engine loading
                // without a custom engine build. The patched file is logged
                // here for diagnostics. See docs/IOS_INTEGRATION.md for
                // the custom engine approach.
            } else {
                NSLog("[PatchflyLoader] WARNING: Patched file missing at \(activePath)")
            }
        } else {
            NSLog("[PatchflyLoader] No patched engine — using bundled App.framework")
        }

        super.viewDidLoad()
    }
}

// MARK: - App Restart Handler

/// Extension to handle app restart after patch apply.
/// When a patch is staged, PatchflyPlugin posts a notification.
/// The AppDelegate should observe this and recreate the root VC.
extension Notification.Name {
    /// Posted when a patch has been staged and the app should restart
    /// to pick it up.
    static let PatchflyRestartRequired = Notification.Name("PatchflyRestartRequired")
}

/// Helper to add restart observation to AppDelegate
public class PatchflyRestartHelper {

    /// Call from AppDelegate.application(_:didFinishLaunchingWithOptions:)
    /// to observe restart requests.
    public static func observeRestart(in delegate: UIApplicationDelegate) {
        NotificationCenter.default.addObserver(
            forName: .PatchflyRestartRequired,
            object: nil,
            queue: .main
        ) { _ in
            NSLog("[Patchfly] Restart requested — recreating root VC...")

            // Give a small delay for the method channel to return
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let window = (delegate as? UIResponder)?.window ?? UIApplication.shared.windows.first {
                    // Recreate the Flutter VC — on next viewDidLoad,
                    // PatchflyFlutterViewController will check for patched engine
                    let newVC = PatchflyFlutterViewController()
                    UIView.transition(
                        with: window,
                        duration: 0.3,
                        options: .transitionCrossDissolve,
                        animations: {
                            window.rootViewController = newVC
                        }
                    )
                }
            }
        }
    }
}
