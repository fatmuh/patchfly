package dev.patchfly

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Patchfly Android plugin — manages the on-device patch lifecycle.
 *
 * ## Flow
 *
 * 1. SDK downloads a patch from the server and saves it to
 *    `<filesDir>/patchfly/patches/<sha256>.so`. SHA256 is in the filename
 *    so the verifier can re-check integrity without extra metadata.
 *
 * 2. SDK calls `apply()` here. We move/rename the file to the canonical
 *    "active" name so the next app launch can find it.
 *
 * 3. We schedule a process restart. On the next launch,
 *    [PatchflyApplication] runs in `attachBaseContext()` BEFORE Flutter
 *    engine loads. It:
 *      - finds `<filesDir>/patchfly/patches/active.so`
 *      - verifies the SHA256 in the sidecar `<filesDir>/patchfly/patches/active.sha256`
 *      - calls `System.load(absolutePath)` which `dlopen`s the file
 *        into the process with the filename `libapp.so`
 *
 * 4. When the Flutter engine later calls `dlopen("libapp.so")`, the
 *    dynamic linker finds the already-loaded copy and uses it.
 *
 * ## Caveat
 *
 * This works on Android 5+ and Flutter 3.7+. For a production-grade
 * implementation, maintain a Flutter engine fork (see
 * docs/ANDROID_INTEGRATION.md § Production path).
 */
class PatchflyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "patchfly/apply"
        private const val TAG = "Patchfly"

        /** Where the SDK / this plugin stores patches on disk. */
        fun patchDir(ctx: Context): File =
            File(ctx.filesDir, "patchfly/patches").apply { mkdirs() }

        /** The "currently active" patch — renamed by `apply()`. */
        fun activePatchFile(ctx: Context): File =
            File(patchDir(ctx), "active.so")

        /** Sidecar file containing the SHA256 of the active patch. */
        fun activePatchShaFile(ctx: Context): File =
            File(patchDir(ctx), "active.sha256")
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        when (call.method) {
            "apply" -> {
                val path = call.argument<String>("path")
                val sha256 = call.argument<String>("sha256")
                val patchNumber = call.argument<Int>("patchNumber")
                if (path == null) {
                    result.error("ARG_MISSING", "path is required", null)
                    return
                }
                if (patchNumber == null) {
                    result.error("ARG_MISSING", "patchNumber is required", null)
                    return
                }
                try {
                    applyPatch(path, patchNumber, sha256)
                    result.success(mapOf("applied" to true, "path" to path, "patchNumber" to patchNumber))
                } catch (e: Exception) {
                    Log.e(TAG, "Apply failed", e)
                    result.error("APPLY_FAILED", e.message, null)
                }
            }
            "verify" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("ARG_MISSING", "path is required", null)
                    return
                }
                try {
                    val exists = File(path).exists()
                    result.success(mapOf("exists" to exists, "path" to path))
                } catch (e: Exception) {
                    result.error("VERIFY_FAILED", e.message, null)
                }
            }
            "getActivePath" -> {
                val p = PatchflyNative.shorebirdActivePath()
                result.success(p)
            }
            "getActivePatchNumber" -> {
                val n = PatchflyNative.shorebirdActivePatchNumber()
                result.success(n)
            }
            "isUpdaterAvailable" -> {
                result.success(PatchflyNative.isAvailable)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Stage a downloaded patch into the location the native updater expects,
     * then trigger a process restart.
     *
     * Native updater cache layout:
     *   `<cacheDir>/patches/<patchNumber>/libapp.so`  (full file)
     *   `<cacheDir>/patches/<patchNumber>/patch.bin`  (bsdiff)
     *
     * On the next launch, [PatchflyApplication.tryInitUpdater] calls
     * `shorebird_update()` which finds the patch and applies it.
     * [PatchflyFlutterLoader] then points the engine at the patched file.
     */
    private fun applyPatch(patchPath: String, patchNumber: Int, expectedSha256: String?) {
        val ctx = appContext ?: throw IllegalStateException("No context")
        val src = File(patchPath)
        if (!src.exists()) {
            throw IllegalStateException("Patch file not found: $patchPath")
        }

        // Stage at <cacheDir>/patches/<patchNumber>/libapp.so
        val patchDir = File(ctx.cacheDir, "patches/$patchNumber")
        patchDir.mkdirs()
        val dst = File(patchDir, "libapp.so")
        if (dst.exists()) dst.delete()
        src.copyTo(dst, overwrite = true)

        // Also write the SHA256 sidecar so the native updater can verify
        // integrity (it currently does ELF magic only, but a future
        // enhancement could use this).
        if (expectedSha256 != null) {
            File(patchDir, "libapp.so.sha256").writeText(expectedSha256)
        }

        // Persist a "patch ready" flag for debugging
        val prefs = ctx.getSharedPreferences("patchfly", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("active_patch_path", dst.absolutePath)
            .putString("active_patch_sha256", expectedSha256)
            .putInt("active_patch_number", patchNumber)
            .putLong("active_patch_installed_at", System.currentTimeMillis())
            .apply()

        // Write active patch number to a simple file so the Dart side
        // can read it on the next launch (before MethodChannel is wired).
        // Also write to Flutter's SharedPreferences for the same purpose.
        try {
            val marker = File(ctx.filesDir, "patchfly/active_patch_number")
            marker.parentFile?.mkdirs()
            marker.writeText("$patchNumber")
            Log.i(TAG, "Wrote marker file: ${marker.absolutePath} -> $patchNumber")
        } catch (t: Throwable) {
            Log.e(TAG, "Could not write active_patch_number file: $t")
        }
        try {
            val flutterPrefs = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            flutterPrefs.edit()
                .putInt("flutter.patchfly_active_patch_number", patchNumber)
                .commit() // synchronous flush before process kill
            Log.i(TAG, "Wrote FlutterSharedPreferences: flutter.patchfly_active_patch_number = $patchNumber")
        } catch (t: Throwable) {
            Log.e(TAG, "Could not write Flutter SharedPreferences: $t")
        }

        Log.i(TAG, "Patch staged for next launch: ${dst.absolutePath} (patch #$patchNumber)")

        // Restart the process so PatchflyApplication.attachBaseContext()
        // runs again and the native updater picks up the new patch.
        Handler(Looper.getMainLooper()).post {
            val launchIntent = ctx.packageManager
                .getLaunchIntentForPackage(ctx.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(
                    android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                    android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK
                )
                ctx.startActivity(launchIntent)
            }
            // Kill this process; the new one will load the patched library.
            android.os.Process.killProcess(android.os.Process.myPid())
            System.exit(0)
        }
    }
}
