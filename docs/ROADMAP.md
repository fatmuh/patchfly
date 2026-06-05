# Roadmap

What works today, what's next.

## ✅ MVP (this commit)

- [x] Server: Dart + Shelf + PostgreSQL
- [x] Auth: email/password, JWT for web, API keys for CLI, SDK keys for mobile
- [x] Apps: register, list, delete, rotate SDK key
- [x] Channels: stable, beta, internal (auto-created per app)
- [x] Releases: create, list, with version + notes
- [x] Patches: upload (multipart), sha256 verify, sign with ed25519
- [x] SDK: init, check, download, signature verify, telemetry
- [x] CLI: full workflow — login, apps, releases, patch, promote, rollout
- [x] Android plugin: receives apply() call and restarts app
- [x] Docker compose for local dev and prod
- [x] Staged rollouts (server-side hash-bucketing)
- [x] Telemetry: check, download, apply, error events
- [x] Nginx + Let's Encrypt config

## 🚧 In progress

- [ ] Android `dlopen()` mechanism (needs custom Gradle plugin)
- [ ] Admin dashboard (web UI for the server)
- [ ] iOS support (later)

## 📋 Next (post-MVP)

### Reliability
- [x] Object storage backend (S3 / MinIO / R2 / B2) — done, swappable via `STORAGE_BACKEND`
- [ ] Differential patches (bsdiff — only send deltas, not full libapp.so)
- [ ] Patch deduplication (same content across releases)
- [ ] Automatic rollback if apply() error rate spikes

### UX
- [ ] Web dashboard: list apps, releases, patches, see telemetry
- [ ] CLI: `patchfly diff <patchA> <patchB>` — compare two patches
- [ ] Slack/Discord notifications on patch events

### Commercial
- [ ] Multi-tenant orgs (one user, many orgs)
- [ ] Billing (Stripe) — pay per patch / per MAU
- [ ] Usage-based limits
- [ ] Self-serve signup

### iOS
- [ ] Investigate App Store rules around code push
- [ ] Explore JIT-disabled interpreter mode
- [ ] Native `dylib` patching (very tricky)

### Platform support
- [ ] macOS, Windows, Linux desktop
- [ ] Web (impossible — bundles are JS, no AOT)

## 🛑 Explicitly out of scope

- Reverting to a previous Dart SDK version (compile-time toolchain)
- Patching native plugins (compiled C++ code in APK)
- Patching assets via code push (use a CDN for that)
- Bypassing App Store review (we don't help you do that)
