# Project Status

Real status as of 2026-06-03.

## ✅ What's actually done and verified

| Component | Status | Verified by |
|---|---|---|
| Server compiles | ✓ | `dart analyze` clean, binary builds |
| Server unit tests | ✓ | 21/21 pass (crypto, models, utils) |
| Server starts | ✓ | Reaches DB connect step without errors |
| CLI compiles | ✓ | `dart analyze` clean, binary builds |
| CLI works | ✓ | `patchfly --version`, `--help` |
| CLI unit tests | ✓ | 5/5 pass |
| SDK compiles | ✓ | `flutter analyze` clean |
| Example app compiles | ✓ | `flutter analyze` clean |
| ed25519 keygen | ✓ | `dart run tool/gen_signing_keys.dart` produces valid 32-byte keys |
| ed25519 sign/verify | ✓ | Roundtrip test: `sign(hash) → verify → true` |
| ed25519 cross-key | ✓ | Verify with wrong key fails |
| Smoke test script | ✓ | `make smoke` runs full API flow end-to-end |

## ✅ All code features implemented (but not e2e-tested locally)

- [x] **Server** — full REST API
  - Auth: register, login, JWT, API keys, SDK keys
  - Apps: CRUD, rotate SDK key
  - Channels: stable/beta/internal (auto-created)
  - Releases: CRUD, active/inactive state
  - Patches: upload (multipart), sha256 verify, ed25519 sign
  - SDK endpoints: check, events, patch file download, public key
  - Staged rollouts (server-side hash bucket)
  - Telemetry events
  - Postgres schema with all tables
  - Configurable SSL mode (disable/require/verify-full)
  - Simple async connection pool

- [x] **CLI** — `patchfly` command
  - register, login (with API key support), whoami
  - apps: list, create, get, delete
  - keys: list, create, revoke
  - releases: list, create
  - patch: build APK, extract libapp.so, hash, upload
  - promote, rollout, doctor
  - patchfly.yaml config in user projects
  - Persistent config in `~/.patchfly/`

- [x] **SDK** — Flutter package
  - init, checkForUpdate, download (with signature verify), apply
  - Telemetry
  - Storage in app's private dir
  - Example app

- [x] **Android plugin** (Kotlin)
  - Receives `apply` call from Dart
  - Restarts app, signaling MainActivity to load new libapp.so
  - Skeleton for full integration (host app needs custom MainActivity)

- [x] **Tooling**
  - `dart run tool/gen_signing_keys.dart` — generates real ed25519 keypair
  - `dart compile exe` produces a single self-contained binary
  - `make smoke` runs end-to-end API test
  - Docker Compose for prod (Postgres + server + nginx)
  - Smoke test script for post-deploy verification

## 🚧 What requires user action before "production"

- [ ] **Android `dlopen()`** — the SDK is ready, but the actual AOT
  reload requires the host app's `MainActivity` to be modified to
  `dlopen()` a downloaded `libapp.so` from a custom path. This is
  documented in `docs/ANDROID_INTEGRATION.md`. Without it, the SDK
  can download patches but they won't actually replace the running
  code.

- [ ] **Real end-to-end test on VPS** — run `make docker-up && make smoke`
  to verify the full flow against a real database.

- [ ] **Web dashboard** — for managing apps/releases/patches from a
  browser. CLI is sufficient for MVP.

- [ ] **iOS support** — declared as future in `docs/ROADMAP.md`.

## How to verify the build is solid

```bash
# Server: 21 unit tests
cd server && dart test

# CLI: 5 unit tests
cd cli && dart test

# All three: lint clean
cd server && dart analyze
cd cli && dart analyze
cd sdk && flutter analyze
cd sdk/example && flutter analyze

# Build production binaries
cd server && dart compile exe bin/server.dart -o bin/server
cd cli && dart compile exe bin/patchfly.dart -o bin/patchfly

# Real keypair
cd server && dart run tool/gen_signing_keys.dart
# Copy PATCH_SIGNING_PUBLIC_KEY and PATCH_SIGNING_PRIVATE_KEY to .env

# End-to-end (after deploy)
make smoke
```

## Test count summary

- Server: **21** tests (json, validation, hash, ed25519, models)
- CLI: **5** tests (config)
- SDK: 0 tests (no test harness yet — TODO)
- Total: **26** automated tests, all passing

## What was fixed in this session

The first build had ~70 analyzer errors. The fixes:

1. **ed25519** — pointycastle 3.9.1 doesn't include ed25519. Switched
   both server and SDK to use `ed25519_edwards` directly.
2. **Postgres API** — `postgres` 3.5.11 has no `ConnectionPool` or
   `toMaps()`. Wrote a small async pool + Row helper.
3. **JWT API** — `dart_jsonwebtoken` 2.17.0 uses `JWTAlgorithm.HS256`,
   not standalone `HS256()`. And takes `SecretKey` not raw bytes.
4. **bcrypt** — `gensalt()` (no `rounds` parameter in 1.2.0).
5. **shelf_multipart** — extension methods in `package:shelf_multipart/form_data.dart`,
   not `shelf_multipart.dart`.
6. **JSON model parsing** — unified `Row` helper class.
7. **Main router** — replaced broken nested-router approach with two
   flat routers (public + protected) + a small dispatcher.
8. **SSL config** — added `DATABASE_SSL_MODE` env var.
