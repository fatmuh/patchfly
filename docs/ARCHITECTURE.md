# Architecture

## High-level

```
┌──────────────────────────────────────────────────────────┐
│                       YOUR TEAM                          │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────┐  │
│  │ Flutter proj │    │ patchfly CLI │    │ patchfly │  │
│  │  (your app)  │    │  (laptop)    │    │  server  │  │
│  └──────┬───────┘    └──────┬───────┘    └────┬─────┘  │
│         │                   │                  │         │
│         │ embeds            │ uploads          │         │
│         │ SDK               │ libapp.so        │         │
└─────────┼───────────────────┼──────────────────┼─────────┘
          │                   │                  │
          │                   │                  │
          ▼                   ▼                  ▼
┌──────────────────────────────────────────────────────────┐
│                  CUSTOMER DEVICES (Android)              │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────┐  │
│  │ Your app     │    │ Patchfly     │    │ Storage  │  │
│  │ (AOT loaded) │◀──▶│ SDK          │───▶│ /libapp  │  │
│  └──────────────┘    └──────────────┘    └──────────┘  │
└──────────────────────────────────────────────────────────┘
```

## Components

### 1. Patchfly Server

Dart + Shelf + PostgreSQL. Serves a REST API.

**Key responsibilities:**
- Authenticate users (email/password) and CLI (API key)
- Authenticate SDK calls (per-app SDK key in header)
- Store app metadata, releases, patches
- Sign patches with ed25519 private key
- Stream patch files to SDK clients
- Record telemetry events (check, download, apply, error)
- Implement staged rollouts (server-side)

**Storage layout:**
```
/var/patchfly/storage/
└── <release_id>/
    ├── 1_<sha8>.so      <-- patch #1
    ├── 2_<sha8>.so      <-- patch #2
    └── ...
```

### 2. Patchfly CLI

Dart command-line tool that developers run from their Flutter project.

**Key responsibilities:**
- `patchfly login` / `patchfly register` — auth
- `patchfly apps` — register/manage apps
- `patchfly releases` — create/manage releases
- `patchfly patch` — build (or use existing) APK, extract `libapp.so`,
  hash, upload
- `patchfly promote` / `patchfly rollout` — control which patch is
  active and at what percentage

**Patch upload flow:**
```
1. Run `flutter build apk --release` (unless --skip-build)
2. Unzip the APK and extract lib/<abi>/libapp.so
3. Compute sha256
4. POST /api/v1/releases/<id>/patches with multipart
5. Server:
   a. Verifies sha256
   b. Signs the sha256 with ed25519 private key
   c. Stores the file at /var/patchfly/storage/<release_id>/N_<sha8>.so
   d. Returns the patch manifest
6. CLI displays status
```

### 3. Patchfly SDK (Flutter package)

Dart package embedded in the customer's app.

**Key responsibilities:**
- Initialize: fetch server's public key, get app version
- `checkForUpdate()`: POST /sdk/check with current version/channel/device
- `download(update)`: GET /sdk/patch/<id>/file, verify sha256 + signature
- `apply(path)`: MethodChannel call to platform code
- Telemetry: POST /sdk/events for check/download/apply/error

**Signature verification:**
The SDK embeds the server's ed25519 public key (fetched once at init).
Every patch has a `signature` field which is the ed25519 signature of
the patch's sha256 hash. The SDK verifies this before saving.

This means: an attacker who can write to the storage directory but
not the server cannot inject a malicious patch — they don't have the
private key.

### 4. Android platform integration

Kotlin plugin in the SDK. Receives `apply` calls from Dart and
restarts the app with the new `libapp.so` loaded via `dlopen()`.

See [`ANDROID_INTEGRATION.md`](ANDROID_INTEGRATION.md) for the
build-side details.

## Data model

```
User 1 --- * App
            │
            │--- * Channel (stable, beta, internal)
            │       │
            │       └--- * Release
            │                │
            │                └--- * Patch (1, 2, 3, ...)
            │
            └--- * ApiKey (for CLI)

App 1 --- * PatchEvent (telemetry)
```

Key constraints:
- An app belongs to one user
- A release belongs to one channel
- Patches are monotonically numbered per release
- Only one patch is `is_active=true` per release at a time
- Releases on a channel can be active/inactive independently

## Security model

### Threats we defend against

| Threat | Defense |
|---|---|
| Attacker tampers with patch in transit | HTTPS + sha256 verification |
| Attacker uploads malicious patch to server | JWT/API key auth on upload |
| Attacker with DB read access serves malware | Ed25519 signature, public key in app |
| Attacker replay attack (forces downgrade) | Patch number + rollout logic |
| App version mismatch | `min_app_version` / `max_app_version` |
| Compromised CDN/storage | Same: signature check |

### Threats we don't (yet) defend against

- Compromise of the server's private key (game over for all apps)
- Side-channel analysis of patch contents
- User with root on their own device modifying the app
- iOS app store policy violations (we're Android-only for now)

### Key rotation

Keys are loaded from env at startup. To rotate:
1. Generate new key pair
2. Update env
3. Restart server
4. Update `PatchflyConfig` initialization in user apps (next release)
5. Old key remains valid for a grace period

## Rollout semantics

When a patch is created with `rollout_percent=10`, only 10% of devices
will receive it on `checkForUpdate()`. Which 10% is determined by a
**stable hash of the device id**, modulo 100. This is:
- Deterministic: same device always falls in the same bucket
- Well-distributed: FNV-1a is good enough for this
- Bump-safe: if you raise to 20%, the original 10% is included

The device-side also gates with a 0-99 random number to prevent the
server from being able to "force" a specific device to update. (The
client decides on its own whether to actually apply.)

## Telemetry

The SDK records four event types:
- `check` — every `/sdk/check` call
- `download` — patch downloaded
- `apply` — patch applied successfully
- `error` — patch failed to apply (with error message)

These are visible via the server's admin endpoints (TODO: a
dashboard). For now, query the `patch_events` table directly.

## Why not Flutter's hot reload / hot restart?

Hot reload requires a debugger connection (DTD). It only works in
profile/debug mode. Production apps are in release mode with AOT
compilation, so the only way to push code is to ship new AOT
binaries — which is what we do.

## What Shorebird does differently

Shorebird keeps their build process opaque. Patchfly is open about
the AOT mechanism and lets you plug in your own signing, your own
storage backend (S3/MinIO), your own auth. Trade-off: more work for
you to set up; more control long-term.
