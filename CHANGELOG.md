# Changelog

All notable changes to Patchfly will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **TL;DR** — Patchfly is a Shorebird-style OTA update tool for Flutter. The CLI
> (`patchfly`) ships code patches (compiled `libapp.so` diffs) to your app
> without going through the app store. This repo is the private source.
> Public artifacts live at:
> - Installer: [`fatmuh/patchfly-install`](https://github.com/fatmuh/patchfly-install)
> - Downloads: `https://cdn.patchfly.dev/cli/<version>/...`
> - Updater engine: [`fatmuh/patchfly-updater`](https://github.com/fatmuh/patchfly-updater)
> - Sample app: [`fatmuh/patchfly-sample`](https://github.com/fatmuh/patchfly-sample) _(coming soon)_

---

## [0.1.1] - 2026-06-06

### Fixed
- **CLI version mismatch**: `--version` now reports the correct version
  matching the release tag. Previously the binary reported `0.1.0` (a
  hardcoded value) but releases were tagged `v0.0.2`, leaving users
  confused. Version is now injected at compile time via
  `dart compile exe --define=VERSION=<x>`, so the binary's reported
  version always matches its tag.
- **Release workflow**: `Resolve version` step on the build matrix had
  a bash syntax typo (`]]` instead of `]`) that crashed the
  windows-latest job. Fixed and added `shell: bash` explicitly.
- **Release workflow**: `VERSION` bash variable set in `Resolve version`
  was not carried over to the `Build CLI` step. Fixed by exposing
  it as a step output and passing it via `env: VERSION: ${{ steps.ver.outputs.version }}`.
- **Release workflow**: removed temporary debug `strings`/`echo` checks
  used to diagnose the version issue.

---

## [0.0.2] - 2026-06-05

### Added
- **CLI: `patches` subcommand** (`list`, `get`, `promote`) — the new
  canonical way to manage patches. Replaces the old top-level
  `patchfly promote` command which had confusing UUID handling.
- **CLI: `patches promote <number> --app <slug>`** — activate a patch
  by its number, no need to look up release IDs.
- **CLI: `--help` on every subcommand** (13 commands total: `init`,
  `login`, `register`, `apps`, `releases`, `patch`, `patches`,
  `promote`, `rollout`, `keys`, `assets`, `doctor`, `whoami`).
- **CLI: `--json` flag** on `apps`, `releases`, `patches`, `keys` for
  piping into `jq` and other tools.
- **CLI: `releases list --all`** to see every release across all apps.
- **CLI: `patches list --app <slug>`** (the `patches` subcommand
  itself didn't exist before).
- **CLI: comprehensive `cli/README.md`** documenting every command
  with syntax, options, examples, and sample output.

### Changed
- **`patchfly promote` is now a deprecation alias** that forwards to
  `patches promote` with a warning. Will be removed in a future release.
- **`patchfly doctor` is now graceful** — won't crash with raw
  `ProcessException` if `flutter` or `unzip` aren't installed; shows
  helpful warnings instead.

### Fixed
- **CLI: `apps get <slug>` and `apps delete <slug>`** were broken
  (positional arg bug — used `result.rest` instead of
  `result.command!.rest`).
- **CLI: `patches get <id>`** had the same positional arg bug.
- **Server: `downloadUrl` was empty in 5 of 6 patch endpoints**
  (`list`, `upload` response, `update`, `activate`, `rollout`). Only
  the `get` endpoint was returning a URL, and it was using
  `http://localhost:8080` because the server didn't know its public
  base URL. Now all endpoints consistently use a `_downloadUrl(id)`
  helper.
- **Server: `PATCHFLY_*` env vars fallback to `PULTFLUT_*`**.
  Existing Dokploy deployments were still setting
  `PULTFLUT_BASE_URL` (etc.) from before the rebrand; the new
  `PATCHFLY_BASE_URL` names were silently ignored. `env()`,
  `envOpt()`, `envInt()`, and `envBool()` now check `PATCHFLY_<key>`
  first and fall back to `PULTFLUT_<key>` for backward compat.

---

## [0.0.1] - 2026-06-04

First public release. End-to-end OTA patch delivery works on real
Android devices (verified on Redmi Note 8 with test app
`com.example.test`).

### Added

**Infrastructure**
- Rebrand from **Pultflut** to **Patchfly** (all references, repos,
  packages, env vars, install scripts).
- Public download CDN at `https://cdn.patchfly.dev` (Cloudflare in
  front of an IDCloudHost RGW bucket literally named
  `cdn.patchfly.dev`).
- One-line installer (Shorebird-style) — Windows / macOS / Linux,
  no env vars required:
  ```powershell
  iwr -UseBasicParsing 'https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.ps1'|iex
  ```
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.sh | bash
  ```
- SHA-256 verification for every download
  (per-file `.sha256` + top-level `SHA256SUMS`).
- Server URL: `https://api.patchfly.dev` (Dokploy + Cloudflare).
- Source stays 100% private in `fatmuh/patchfly`.

**CLI (`patchfly`)**
- `patchfly init` — generate `patchfly.yaml` for a Flutter project.
- `patchfly login` — email/password (interactive or flags) or
  paste an API key.
- `patchfly register` — create a new Patchfly account.
- `patchfly whoami` — show current user and apps.
- `patchfly apps create | list | get | delete` — manage apps.
- `patchfly keys create | list | revoke` — manage API keys
  (for CI/CD).
- `patchfly releases create | list` — manage releases per app.
- `patchfly patch --app <slug>` — the main "ship it" command:
  builds `flutter build apk --release`, extracts `libapp.so`,
  hashes, uploads, and (by default) activates the patch.
- `patchfly rollout --patch <id> --percent <n>` — adjust rollout
  percentage for staged rollouts.
- `patchfly assets push | list` — manage pure asset bundles.
- `patchfly doctor` — sanity check environment + server.
- Global flags: `--server`, `--json`, `--verbose`, `--help`.

**Server (`api.patchfly.dev`)**
- REST API: apps, releases, patches, keys, auth.
- JWT + API key auth.
- Multipart upload for patches with `sha256` verification.
- Release + patch model: `is_active`, `rollout_percent`,
  `min_app_version`, `max_app_version` for targeted rollouts.
- Patch download endpoint with signature verification.
- Postgres backend.

**SDK (`fatmuh/patchfly-updater`)**
- Native Rust engine (JNI shim) for Android AOT patch verification.
- Dart SDK wrapper for `Patchfly.init()` /
  `Patchfly.checkForUpdate()`.
- Compatible with Flutter 3.44.1 / Dart 3.12.1.

---

## Versioning policy

- **0.0.x** — pre-1.0 development releases. May include breaking
  changes between minor versions.
- **0.1.x** — first "real" releases once the CLI + server + SDK are
  stable enough for public use. Backward-compat for env var names
  (PULTFLUT_* vs PATCHFLY_*) is maintained.
- **1.0.0** — public API stable, no breaking changes without a
  major version bump.

## How to upgrade

Just reinstall via the one-liner (above). It always fetches the
latest from `https://cdn.patchfly.dev/cli/latest/`.

```bash
# Check your current version
patchfly --version

# Reinstall to get the latest
# (use the same one-liner from the top of the README)
```

[Unreleased]: https://github.com/fatmuh/patchfly/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/fatmuh/patchfly/releases/tag/v0.1.1
[0.0.2]: https://github.com/fatmuh/patchfly/releases/tag/v0.0.2
[0.0.1]: https://github.com/fatmuh/patchfly/releases/tag/v0.0.1
