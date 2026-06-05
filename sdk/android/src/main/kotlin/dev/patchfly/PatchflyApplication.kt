package dev.patchfly

import android.app.Application
import android.content.Context
import android.content.pm.PackageInfo
import android.os.Build
import android.util.Log

/**
 * Patchfly base Application class.
 *
 * Wire it up in your `AndroidManifest.xml`:
 * ```xml
 * <application
 *     android:name=".PatchflyApplication"
 *     ...>
 * ```
 *
 * Or extend it:
 * ```kotlin
 * class MyApp : PatchflyApplication()
 * ```
 *
 * ## What it does on every cold start
 *
 * **Stage 1 — `attachBaseContext()`** runs BEFORE the Flutter engine
 * starts. We use it to drive the native updater (`libpatchfly_updater.so`):
 *
 *   1. `shorebird_init(version, cacheDir, libappDir)` — record paths
 *   2. `shorebird_update()` — scan `<cacheDir>/patches/<N>/` for staged
 *      patches, verify (ELF magic for full file, bsdiff apply for delta),
 *      and atomic-rename the result in place. The active path & patch
 *      number are stored inside the library as "sticky" state.
 *
 * **Stage 2 — `onCreate()`** installs [PatchflyFlutterLoader] into the
 * `FlutterInjector` via reflection. The swapped loader's
 * `ensureInitializationComplete` overrides `aotSharedLibraryName` with
 * the absolute path of the patched libapp.so returned by the native
 * updater. The Flutter engine then `dlopen()`s our patched library
 * instead of the bundled one.
 *
 * ## Cache layout (written by [PatchflyPlugin.apply])
 *
 * ```
 * <cacheDir>/patches/<patchNumber>/libapp.so           (full file)
 * <cacheDir>/patches/<patchNumber>/libapp.so.sha256    (optional sidecar)
 * <cacheDir>/patches/<patchNumber>/patch.bin           (bsdiff delta)
 * ```
 *
 * The plugin's `apply` MethodChannel handler stages the downloaded
 * patch into this layout. On the next cold start, this Application
 * class picks it up via `shorebird_update()`.
 *
 * ## Fallback semantics
 *
 * Every native call is wrapped and failures are logged but never
 * thrown. If anything goes wrong (library missing, corrupt patch,
 * ABI mismatch, etc.), the app falls through to the bundled libapp.so
 * and shows the original UI. The patch will be retried on the next
 * launch once the underlying issue is resolved.
 *
 * ## Why this works without a Flutter engine fork
 *
 * See `PatchflyFlutterLoader.kt` for the deep dive. Short version:
 * the engine builds two `--aot-shared-library-name=` flags
 * (relative + absolute). We make the *first* one our absolute
 * patched path; `dlopen()` of an absolute path bypasses the linker
 * search that would otherwise resolve `libapp.so` to the bundled copy
 * next to `libflutter.so`.
 */
open class PatchflyApplication : Application() {

    companion object {
        private const val TAG = "Patchfly"
    }

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        // Earliest hook before the Flutter engine starts. Safe to call
        // native init here — the C side just sets thread-local state.
        tryInitNativeUpdater(base)
    }

    override fun onCreate() {
        super.onCreate()
        // Swap the FlutterLoader in the FlutterInjector. Must happen
        // before the first FlutterActivity is created (which happens
        // immediately after Application.onCreate returns).
        PatchflyFlutterLoader.install()
    }

    /**
     * Initialize the native updater and apply any pending patches.
     *
     * All failures are logged; never thrown. The app must always
     * start successfully even when the updater is missing.
     */
    private fun tryInitNativeUpdater(ctx: Context) {
        if (!PatchflyNative.isAvailable) {
            Log.w(TAG, "libpatchfly_updater.so not loaded; skipping native init")
            return
        }

        val version = readVersionString()
        val cacheDir = ctx.cacheDir.absolutePath
        val libappDir = try {
            ctx.applicationInfo.nativeLibraryDir
        } catch (t: Throwable) {
            Log.w(TAG, "Could not read nativeLibraryDir: $t")
            ""
        }

        Log.i(
            TAG,
            "Init native updater: version=$version cache=$cacheDir libappDir=$libappDir"
        )

        val initRc = PatchflyNative.shorebirdInit(version, cacheDir, libappDir)
        if (initRc != 0) {
            Log.e(TAG, "shorebirdInit returned $initRc — falling back to bundled libapp.so")
            return
        }

        val updateRc = PatchflyNative.shorebirdUpdate()
        if (updateRc != 0) {
            // Non-zero means a patch was present but failed to apply
            // (corrupt, wrong base, ELF magic mismatch, etc.). Log it
            // and fall through — the next launch will retry with the
            // same staged patch.
            Log.e(TAG, "shorebirdUpdate returned $updateRc — using bundled libapp.so")
        }

        val activePath = PatchflyNative.shorebirdActivePath()
        val activePatch = PatchflyNative.shorebirdActivePatchNumber()
        Log.i(
            TAG,
            "Native updater ready: activePath=$activePath activePatch=$activePatch"
        )
    }

    /**
     * Read `"<versionName>+<versionCode>"` from [PackageInfo],
     * matching the format the Dart side uses via `package_info_plus`
     * (e.g. `1.0.0+1`).
     */
    @Suppress("DEPRECATION")
    private fun readVersionString(): String {
        return try {
            val pi: PackageInfo = packageManager.getPackageInfo(packageName, 0)
            val name = pi.versionName ?: "0.0.0"
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pi.longVersionCode
            } else {
                pi.versionCode.toLong()
            }
            "$name+$code"
        } catch (t: Throwable) {
            Log.w(TAG, "Could not read package version: $t")
            "0.0.0+0"
        }
    }
}
