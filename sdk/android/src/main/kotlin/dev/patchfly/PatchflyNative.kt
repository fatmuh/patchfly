package dev.patchfly

import android.util.Log

/**
 * Kotlin bindings for `libpatchfly_updater.so` (Rust native library).
 *
 * This object loads the .so and exposes its C API to Kotlin via JNI.
 * The .so must be packaged in the APK's `jniLibs/<abi>/` directory.
 *
 * ## API surface
 *
 * - [shorebirdInit] — call once at app startup
 * - [shorebirdUpdate] — call to apply available patches
 * - [shorebirdActivePath] — returns path to patched libapp.so (or bundled)
 * - [shorebirdActivePatchNumber] — returns active patch number (or null)
 *
 * The C functions in `libpatchfly_updater.so`:
 * - `Java_dev_patchfly_PatchflyNative_shorebirdInit`
 * - `Java_dev_patchfly_PatchflyNative_shorebirdUpdate`
 * - `Java_dev_patchfly_PatchflyNative_shorebirdActivePath`
 * - `Java_dev_patchfly_PatchflyNative_shorebirdActivePatchNumber`
 *
 * See `patchfly-updater/src/jni_shim.rs` for the Rust side.
 */
object PatchflyNative {
    private const val TAG = "PatchflyNative"

    @Volatile
    private var loaded = false

    init {
        try {
            System.loadLibrary("patchfly_updater")
            loaded = true
            Log.i(TAG, "✓ libpatchfly_updater.so loaded")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "✗ Failed to load libpatchfly_updater.so: ${e.message}")
        }
    }

    val isAvailable: Boolean
        get() = loaded

    /**
     * Initialize the updater state.
     *
     * @param version App version (e.g., "1.0.0+1")
     * @param cacheDir App cache directory (e.g., context.cacheDir.absolutePath)
     * @param libappDir Directory containing bundled libapp.so
     *                  (e.g., context.applicationInfo.nativeLibraryDir)
     * @return 0 on success, non-zero on error
     */
    fun shorebirdInit(version: String, cacheDir: String, libappDir: String): Int {
        if (!loaded) return -1
        return nativeShorebirdInit(version, cacheDir, libappDir)
    }

    /**
     * Check for and apply pending patches in cache.
     *
     * @return 0 on success (whether or not a patch was applied), non-zero on error
     */
    fun shorebirdUpdate(): Int {
        if (!loaded) return -1
        return nativeShorebirdUpdate()
    }

    /**
     * Get the path to the libapp.so that the engine should load.
     *
     * If no patch is active, returns the bundled path. If a patch is active,
     * returns the path to the patched libapp.so in cache.
     *
     * @return Path string, or null on error / not loaded
     */
    fun shorebirdActivePath(): String? {
        if (!loaded) return null
        return nativeShorebirdActivePath()
    }

    /**
     * Get the patch number of the active patch.
     *
     * @return Patch number (e.g., "1"), or null if no patch is active
     */
    fun shorebirdActivePatchNumber(): String? {
        if (!loaded) return null
        return nativeShorebirdActivePatchNumber()
    }

    // JNI bindings (resolved by System.loadLibrary)
    // Function names map to Java_dev_patchfly_PatchflyNative_<name> in
    // patchfly-updater/src/jni_shim.rs
    @JvmStatic
    private external fun nativeShorebirdInit(
        version: String,
        cacheDir: String,
        libappDir: String
    ): Int

    @JvmStatic
    private external fun nativeShorebirdUpdate(): Int

    @JvmStatic
    private external fun nativeShorebirdActivePath(): String?

    @JvmStatic
    private external fun nativeShorebirdActivePatchNumber(): String?
}
