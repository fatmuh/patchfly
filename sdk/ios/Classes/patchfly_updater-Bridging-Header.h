//
//  patchfly_updater-Bridging-Header.h
//  patchfly
//
//  Bridging header to expose the Rust native updater C API to Swift.
//  Xcode auto-generates Swift bindings from these declarations.
//
//  The Rust static library (libpatchfly_updater.a) is built from
//  the patchfly-updater repo and exposes these C functions.
//

#ifndef patchfly_Bridging_Header_h
#define patchfly_Bridging_Header_h

#include <stddef.h>

/// Initialize the native updater. Call once at app startup.
/// Returns 0 on success, non-zero on error.
int shorebird_init(const char *release_version,
                   const char *cache_dir,
                   const char *libapp_dir);

/// Check for and apply pending patches in cache.
/// Returns 0 on success, non-zero on error.
int shorebird_update(void);

/// Get the path to the engine binary that should be loaded.
/// Caller must free with shorebird_free_string().
/// Returns NULL on error / not initialized.
const char *shorebird_active_path(void);

/// Get the active patch number as a string.
/// Returns NULL if no patch is active.
const char *shorebird_active_patch_number(void);

/// Free a string returned by shorebird_active_path() or
/// shorebird_active_patch_number(). Safe to call with NULL.
void shorebird_free_string(char *s);

#endif /* patchfly_Bridging_Header_h */
