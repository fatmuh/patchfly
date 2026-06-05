package dev.patchfly

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.loader.FlutterApplicationInfo
import io.flutter.embedding.engine.loader.FlutterLoader
import java.io.File

/**
 * Subclass of [FlutterLoader] that overrides the libapp.so path with
 * the patched one (if available) before the engine starts.
 *
 * ## How it works
 *
 * The default FlutterLoader flow:
 * ```
 * startInitialization()
 *   → flutterApplicationInfo = ApplicationInfoLoader.load(...)  // bundled
 * ensureInitializationComplete()
 *   → builds shell args using flutterApplicationInfo
 *   → engine dlopens <nativeLibraryDir>/libapp.so
 * ```
 *
 * We override `ensureInitializationComplete` to:
 *   1. Check if PatchflyNative has an active patched libapp.so path
 *   2. If yes, replace `flutterApplicationInfo.nativeLibraryDir` with
 *      the directory containing the patched file
 *   3. Then call super, which now uses the patched path
 *
 * ## Installation
 *
 * The PatchflyApplication calls [install] to swap the FlutterLoader
 * singleton (via reflection on its private static `instance` field).
 * This must be done BEFORE FlutterActivity is created.
 */
open class PatchflyFlutterLoader : FlutterLoader() {

    companion object {
        private const val TAG = "PatchflyLoader"

        /**
         * Replace the FlutterLoader used by the engine with [PatchflyFlutterLoader].
         * Must be called from Application.onCreate, before any Activity is created.
         *
         * In modern Flutter (3.10+), the engine obtains its loader via
         * `FlutterInjector.instance().flutterLoader()`. The static `FlutterLoader.instance`
         * pattern is no longer used, so we must install our loader into the FlutterInjector.
         */
        @JvmStatic
        fun install() {
            try {
                val injectorClass = Class.forName("io.flutter.FlutterInjector")
                val instanceField = injectorClass.getDeclaredField("instance")
                instanceField.isAccessible = true

                val currentInjector = instanceField.get(null)
                if (currentInjector != null) {
                    // Read the current flutterLoader from the injector
                    val getFlutterLoader = currentInjector.javaClass.getMethod("flutterLoader")
                    val currentLoader = getFlutterLoader.invoke(currentInjector) as? FlutterLoader
                    if (currentLoader is PatchflyFlutterLoader) {
                        Log.i(TAG, "FlutterInjector already has PatchflyFlutterLoader; skipping")
                        return
                    }
                    Log.i(TAG, "Current FlutterInjector loader: $currentLoader")
                } else {
                    Log.w(TAG, "FlutterInjector.instance was null")
                }

                // Build a new FlutterInjector with our loader
                val builderClass = Class.forName("io.flutter.FlutterInjector\$Builder")
                val setFlutterLoader = builderClass.getMethod("setFlutterLoader", FlutterLoader::class.java)
                val buildMethod = builderClass.getMethod("build")

                val builder = builderClass.getDeclaredConstructor().newInstance()
                val patchfly = PatchflyFlutterLoader()
                setFlutterLoader.invoke(builder, patchfly)
                val newInjector = buildMethod.invoke(builder)

                instanceField.set(null, newInjector)
                Log.i(TAG, "✓ FlutterInjector replaced with PatchflyFlutterLoader")
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to install PatchflyFlutterLoader", e)
            }
        }
    }

    override fun ensureInitializationComplete(
        applicationContext: Context,
        args: Array<String>?
    ) {
        Log.i(TAG, "ensureInitializationComplete called on PatchflyFlutterLoader (this=$this)")
        tryPatchFlutterApplicationInfo()
        super.ensureInitializationComplete(applicationContext, args)
    }

    /**
     * If the native updater has an active patched libapp.so, override
     * the `flutterApplicationInfo.nativeLibraryDir` field so the engine
     * loads from there.
     */
    private fun tryPatchFlutterApplicationInfo() {
        Log.i(TAG, "tryPatchFlutterApplicationInfo: querying native active path...")
        val activePath = PatchflyNative.shorebirdActivePath()
        Log.i(TAG, "tryPatchFlutterApplicationInfo: activePath=$activePath")
        if (activePath == null) {
            Log.i(TAG, "No active patched libapp.so; using bundled")
            return
        }

        val patchedFile = File(activePath)
        if (!patchedFile.exists()) {
            Log.w(TAG, "Active path returned but file missing: $activePath")
            return
        }
        val patchedDir = patchedFile.parent ?: return
        val patchedName = patchedFile.name

        try {
            val infoField = FlutterLoader::class.java.getDeclaredField("flutterApplicationInfo")
            infoField.isAccessible = true
            val original = infoField.get(this) as? FlutterApplicationInfo
            if (original == null) {
                Log.w(TAG, "flutterApplicationInfo is null (startInitialization not called yet?)")
                return
            }
            Log.i(TAG, "tryPatchFlutterApplicationInfo: original nativeLibraryDir=${original.nativeLibraryDir}")

            if (original.nativeLibraryDir == patchedDir &&
                original.aotSharedLibraryName == patchedName
            ) {
                Log.i(TAG, "Already patched; no-op")
                return
            }

            // FlutterApplicationInfo.automaticallyRegisterPlugins is
            // package-private in Flutter, so we read it via reflection
            // and pass the value through to the new instance.
            val arpField = FlutterApplicationInfo::class.java.getDeclaredField("automaticallyRegisterPlugins")
            arpField.isAccessible = true
            val arp = arpField.getBoolean(original)

            // CRITICAL: Set aotSharedLibraryName to the FULL absolute path of
            // the patched file. The FlutterLoader passes TWO args to the engine:
            //   1. "--aot-shared-library-name=libapp.so"  (relative, resolves to bundled)
            //   2. "--aot-shared-library-name=<dir>/libapp.so"  (absolute)
            // The engine iterates application_library_paths in order, and
            // dlopen("libapp.so") succeeds first by finding the bundled one
            // next to libflutter.so. We set the FIRST arg to our absolute
            // path so it wins. The second arg becomes broken (double slash)
            // but the engine never tries it because the first succeeded.
            val fullPatchedPath = "$patchedDir/$patchedName"

            val patched = FlutterApplicationInfo(
                fullPatchedPath,                          // aotSharedLibraryName = absolute path
                original.vmSnapshotData,
                original.isolateSnapshotData,
                original.flutterAssetsDir,
                original.domainNetworkPolicy,
                original.nativeLibraryDir,                // keep bundled dir for libflutter.so
                arp
            )
            infoField.set(this, patched)

            Log.i(
                TAG,
                "✓ Patched FlutterApplicationInfo: aotSharedLibraryName=${original.aotSharedLibraryName} → $fullPatchedPath (nativeLibraryDir kept: ${original.nativeLibraryDir})"
            )
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to patch FlutterApplicationInfo", t)
        }
    }
}
