# Patchfly CLI

Build, upload, and manage OTA updates for your Flutter apps — from the command line.

> **One-line install** (Windows / macOS / Linux): see [`patchfly-install`](https://github.com/fatmuh/patchfly-install) repo.

## Quick start

```bash
# 1. Log in (or register first)
patchfly register --email me@example.com --password mypass
# or
patchfly login

# 2. Register your app
patchfly apps create --slug com.acme.myapp --name "Acme App"
# Save the SDK key it prints — you'll need it in your Flutter app.

# 3. Init a Flutter project (writes patchfly.yaml)
cd path/to/flutter-app
patchfly init --app-id com.acme.myapp

# 4. Build a release & upload your first patch
patchfly patch --app com.acme.myapp

# 5. Inspect / manage patches
patchfly patches list --app com.acme.myapp
patchfly patches get <patch-id>
patchfly patches promote 1 --app com.acme.myapp
```

## Global options

These work before any subcommand:

| Flag | Short | Description |
|---|---|---|
| `--server` | `-s` | Server URL (default: `$PATCHFLY_SERVER` or `~/.patchfly/config.json`) |
| `--json` | | Output JSON where supported (for piping into `jq` etc.) |
| `--verbose` | `-V` | Verbose output |
| `--help` | `-h` | Show help |
| `--version` | `-v` | Show version |

## Command reference

Every command supports `--help` for its own full options. Below is a quick overview with examples and the **actual output** you'll see.

---

### `patchfly whoami` — show current user

```
$ patchfly whoami
Server:  https://api.patchfly.dev
Email:   admin@patchfly.dev
Auth:    JWT
Apps:    2
  - com.example.patchfly (3be0b96b-5ee8-466c-b5b8-65724a3d657f)
  - com.example.test (fb18aece-5dfc-4865-9435-77200efa3f17)
```

| Flag | Description |
|---|---|
| `--help`, `-h` | Show help |

---

### `patchfly login` — log in (email/password or API key)

```
$ patchfly login --email me@example.com --password mypass
✓ Logged in as me@example.com
```

Or with an API key (from `patchfly keys create`):

```
$ patchfly login --api-key pfk_xxxxx
✓ API key saved. Try `patchfly whoami` to verify.
```

| Flag | Short | Description |
|---|---|---|
| `--email` | `-e` | Email (prompts if not given) |
| `--password` | `-p` | Password (prompts if not given, hidden input) |
| `--api-key` | | Paste an API key (e.g. `pfk_...`) |
| `--server` | `-s` | Server URL |

---

### `patchfly register` — create a new account

```
$ patchfly register --email me@example.com --password mypassword --name "Fathur"
✓ Registered and logged in as me@example.com
```

| Flag | Short | Description |
|---|---|---|
| `--email` | `-e` | Email |
| `--password` | `-p` | Password (min 8 chars) |
| `--name` | `-n` | Display name (optional) |
| `--server` | `-s` | Server URL |

---

### `patchfly apps` — manage your apps

#### `patchfly apps list`

```
$ patchfly apps list
SLUG                                     NAME                           PLATFORM   SDK KEY         ID
com.example.patchfly                     Patchfly Example               android    pfk_S9vc        3be0b96b-5ee8-466c-b5b8-65724a3d657f
com.example.test                         Test App                       android    pfk_ZKf4        fb18aece-5dfc-4865-9435-77200efa3f17
```

Add `--json` for machine-readable output:
```
$ patchfly apps list --json | jq '.apps[].slug'
"com.example.patchfly"
"com.example.test"
```

#### `patchfly apps create`

```
$ patchfly apps create --slug com.acme.myapp --name "Acme App"
✓ App created: com.acme.myapp (3be0b96b-...)

SDK key (save now, you cannot see it again):
  pfk_AbCdEf123456...

Put this in your Flutter app (e.g. main.dart):
  Patchfly.init(sdkKey: "pfk_AbCdEf123456...");
```

| Flag | Description |
|---|---|
| `--slug` | Reverse-DNS slug (required), e.g. `com.acme.myapp` |
| `--name` | Display name (required) |
| `--platform` | `android` \| `ios` \| `all` (default: `android`) |

#### `patchfly apps get <slug>`

```
$ patchfly apps get com.acme.myapp
ID:        3be0b96b-5ee8-466c-b5b8-65724a3d657f
Slug:      com.acme.myapp
Name:      Acme App
Platform:  android
SDK key:   pfk_AbCd...
Created:   2026-06-05T09:41:49.492084Z
```

#### `patchfly apps delete <slug>`

```
$ patchfly apps delete com.acme.myapp
✓ Deleted app com.acme.myapp
```

---

### `patchfly releases` — manage releases for an app

#### `patchfly releases list --app <slug>`

```
$ patchfly releases list --app com.example.test
APP                                      VERSION          CHANNEL    ACTIVE  PATCHES  ID
com.example.test                         1.0.0+1          stable     yes     2        30625ab1-85b9-4809-a608-d6127253b049
```

Add `--all` to list every release across all your apps, or `--json` for piping:

```
$ patchfly releases list --all --json | jq '.releases[] | {app, version, id}'
```

| Flag | Short | Description |
|---|---|---|
| `--app` | `-a` | App slug (or pass as positional) |
| `--all` | | List releases for every app you own |
| `--json` | | Output as JSON |

#### `patchfly releases create`

```
$ patchfly releases create --app com.example.test --version 1.2.0+3 --channel stable --notes "Bug fixes"
✓ Created release 1.2.0+3 on stable
  ID:      aea3c732-4bf5-48f9-9c97-98b2f1f45311
  App:     com.example.test
  Notes:   Bug fixes
```

| Flag | Short | Description |
|---|---|---|
| `--app` | `-a` | App slug (required) |
| `--version` | | Version string, e.g. `1.4.2+15` (required) |
| `--channel` | | `stable` \| `beta` \| `internal` \| `alpha` (default: `stable`) |
| `--notes` | | Release notes |

---

### `patchfly patches` — list, inspect, and promote patches

> This is the new canonical command. The old top-level `patchfly promote` is now a deprecated alias that forwards here.

#### `patchfly patches list --app <slug>`

```
$ patchfly patches list --app com.example.test
App:      com.example.test
Release:  30625ab1-85b9-4809-a608-d6127253b049
Patches:  2

#    SHA-256 (16)       SIZE       ROLLOUT  DELTA CREATED              ID
2    bd9a2940b4f29da2   3.8 MB     100%     no    2026-06-05T16:17:38  b5a89965-f833-4e09-a4ce-7d87f3251992
1    390be653061d67f3   3.8 MB     100%     no    2026-06-05T10:03:59  93a31126-37aa-4c83-8c9c-5044a398739b
```

With JSON output:
```
$ patchfly patches list --app com.example.test --json | jq '.patches[-1].id'
"b5a89965-f833-4e09-a4ce-7d87f3251992"
```

| Flag | Short | Description |
|---|---|---|
| `--app` | `-a` | App slug (required) |
| `--release` | | Release ID (default: latest active release) |
| `--json` | | Output as JSON |

#### `patchfly patches get <id>`

```
$ patchfly patches get b5a89965-f833-4e09-a4ce-7d87f3251992
Patch #2
  ID:           b5a89965-f833-4e09-a4ce-7d87f3251992
  SHA-256:      bd9a2940b4f29da2c372003df0454a09d77ff7d353371d3e58548449635baee0
  Signature:    Ri4ZOAFoCT5SWXt2VaXDIqztFQWZnSSKGbvmVfvmg2jlgi/pneTeZnIdYEHxm9Lbl36D0scEdtMi4a4GlWOtAQ==
  Size:         3.8 MB (3933072 bytes)
  Is delta:     false
  Rollout:      100%
  Download URL: https://...
  Created:      2026-06-05T16:17:38.611500Z
```

#### `patchfly patches promote <number> --app <slug>`

Activate a specific patch by its number. Sets rollout to 100%.

```
$ patchfly patches promote 1 --app com.example.test
✓ Patch #1 is now ACTIVE (100% rollout)
  ID:       93a31126-37aa-4c83-8c9c-5044a398739b
  Rollout:  100%
```

| Flag | Short | Description |
|---|---|---|
| `<number>` | (positional) | Patch number to activate (e.g. `1`, `2`, `3`...) |
| `--app` | `-a` | App slug (required) |
| `--json` | | Output as JSON |

**Common workflow** — promote the latest patch via `jq`:
```bash
N=$(patchfly patches list --app com.example.test --json | jq '.patches | length')
patchfly patches promote "$N" --app com.example.test
```

---

### `patchfly patch` — build a release & upload as a patch

This is the main "ship-it" command. It:
1. Runs `flutter build apk --release`
2. Extracts `libapp.so` from the APK
3. Hashes it, uploads to the server
4. Activates it (unless `--no-activate`)

```
$ patchfly patch --app com.example.test
Building Flutter APK (release)...
Extracting libapp.so for arm64-v8a...
libapp.so: 3.8 MB, sha256=bd9a2940...
Uploading patch...
✓ Patch #2 uploaded (3.8 MB)
  ID: b5a89965-f833-4e09-a4ce-7d87f3251992
  Status: ACTIVE (live for all matching devices)
```

| Flag | Short | Description |
|---|---|---|
| `--config` | | Path to `patchfly.yaml` (default: `./patchfly.yaml`) |
| `--app` | `-a` | App slug (overrides `app.slug` in yaml) |
| `--release` | | Specific release ID (default: latest active) |
| `--abi` | | Target ABI: `arm64-v8a` \| `armeabi-v7a` \| `x86_64` (default: `arm64-v8a`) |
| `--channel` | | Channel: `stable` \| `beta` \| `internal` \| `alpha` (default: `stable`) |
| `--rollout` | | Rollout percent `0`-`100` (default: `100`) |
| `--min-app-version` | | Only deliver to apps with version >= this |
| `--max-app-version` | | Only deliver to apps with version <= this |
| `--skip-build` | | Skip `flutter build`, use existing APK |
| `--dry-run` | | Build, but don't upload |
| `--no-activate` | | Upload but don't activate (use `patches promote` later) |

**Staged rollout example:**
```bash
# Start at 10%, monitor, then ramp up
patchfly patch --app com.example.test --rollout 10
patchfly patches promote 1 --app com.example.test     # or rollout below
patchfly rollout --patch <id> --percent 50
patchfly rollout --patch <id> --percent 100
```

---

### `patchfly rollout` — adjust rollout percentage

For staged rollouts without re-uploading.

```
$ patchfly rollout --patch b5a89965-f833-4e09-a4ce-7d87f3251992 --percent 50
✓ Rollout set to 50% for patch #2
```

| Flag | Description |
|---|---|
| `--patch` | Patch ID (required) |
| `--percent` | New rollout percent `0`-`100` (required). `0` = effectively rollback |

---

### `patchfly init` — initialize a Flutter project

Writes a `patchfly.yaml` config file in the current directory.

```
$ patchfly init --app-id com.acme.myapp
✓ Wrote patchfly.yaml
```

| Flag | Short | Description |
|---|---|---|
| `--app-id` | | App slug registered on the server |
| `--channel` | | Default channel (default: `stable`) |
| `--abi` | | Target ABI (default: `arm64-v8a`) |
| `--force` | `-f` | Overwrite existing `patchfly.yaml` |

The generated `patchfly.yaml`:
```yaml
app:
  slug: com.acme.myapp
defaults:
  channel: stable
  abi: arm64-v8a
build:
  apk_path: build/app/outputs/flutter-apk/app-release.apk
```

---

### `patchfly keys` — manage CLI API keys

API keys are how you authenticate the CLI in CI/CD without storing passwords.

#### `patchfly keys list`
```
$ patchfly keys list
API keys:
  pfk_S9vc...  CI runner  last used: 2026-06-04T10:00:00
  pfk_Work...  Work laptop  last used: 2026-06-05T16:00:00
```

#### `patchfly keys create`
```
$ patchfly keys create --name "CI runner" --expires-in-days 90
✓ Created API key: pfk_N3wK3yH3r3...
Save this now. You will not be able to see it again.
To use it:
  patchfly login --api-key pfk_N3wK3yH3r3...
```

#### `patchfly keys revoke <id-or-prefix>`
```
$ patchfly keys revoke pfk_Work
✓ Revoked key pfk_Work...
```

| Flag | Description |
|---|---|
| `--name` | Friendly name for this key (required for `create`) |
| `--expires-in-days` | Optional expiry for `create` |
| `--json` | Output as JSON |

---

### `patchfly assets` — manage asset/config bundles

Most users should use `patchfly patch` (code patches). Use this only for **pure asset/config bundles** (zip files) that ship outside an AOT build.

```
$ patchfly assets push <appId> ./bundle.zip --changelog "New splash screen"
✓ Asset pushed
  Version:  3
  Size:     12345 bytes
  SHA-256:  abc123...

$ patchfly assets list <appId>
{"app":{...}}
```

| Flag | Description |
|---|---|
| `<appId>` (positional) | App ID |
| `<zipPath>` (positional) | Path to the zip file |
| `--changelog` | Changelog text |

---

### `patchfly doctor` — sanity check your environment

```
$ patchfly doctor
Patchfly doctor

✓ flutter: Flutter 3.44.1 • channel stable • https://github.com/flutter/flutter.git
✓ unzip: available
⚠ patchfly.yaml not found. Run `patchfly init` first.

Server: https://api.patchfly.dev
✓ Server reachable
  Version: 0.1.0
✓ Auth: JWT
  Email: admin@patchfly.dev

All checks passed. Ready to ship patches.
```

Run this first if anything goes wrong.

---

### `patchfly promote` — DEPRECATED alias

> ⚠️ Use [`patches promote`](#patchfly-patches-promote-number---app-slug) instead. The old top-level `promote` had confusing UUID handling and required a release ID.

```
$ patchfly promote --app com.example.test --release 30625ab1-... --patch 2
Note: `patchfly promote` is deprecated. Use `patchfly patches promote` instead.
Running: patchfly patches com.example.test 2
```

The deprecation alias still works for now but will be removed in a future release.

---

## Common workflows

### First-time setup

```bash
# Register & log in
patchfly register --email you@example.com --password yourpass

# Register your app
patchfly apps create --slug com.acme.myapp --name "Acme App"
# Note the SDK key it prints.

# Initialize a Flutter project
cd /path/to/flutter-app
patchfly init --app-id com.acme.myapp
# Edit patchfly.yaml to set your app slug if needed

# Build & upload your first patch
patchfly patch --app com.acme.myapp
```

### Staged rollout (canary → 50% → 100%)

```bash
# 1. Upload at 10% (rest of devices won't see it)
patchfly patch --app com.acme.myapp --rollout 10

# 2. Watch metrics, then bump to 50%
PID=$(patchfly patches list --app com.acme.myapp --json | jq -r '.patches[-1].id')
patchfly rollout --patch "$PID" --percent 50

# 3. Roll out to everyone
patchfly rollout --patch "$PID" --percent 100
```

### Roll back

```bash
# Option A: stop delivering a bad patch (sets to 0%)
patchfly rollout --patch <bad-patch-id> --percent 0

# Option B: activate an earlier good patch
patchfly patches promote 1 --app com.acme.myapp
```

### CI/CD (no interactive prompts)

```bash
# Generate an API key locally
patchfly keys create --name "GitHub Actions"

# Use it in CI (in your .github/workflows/*.yml):
#   env:
#     PATCHFLY_SERVER: https://api.patchfly.dev
#   run: |
#     echo "${{ secrets.PATCHFLY_API_KEY }}" | patchfly login --api-key -
#     patchfly patch --app com.acme.myapp --no-activate
#     patchfly patches promote 1 --app com.acme.myapp
```

## Configuration

Config is stored in `~/.patchfly/`:

| File | Contents |
|---|---|
| `config.json` | Server URL, JWT token (or API key), user email |
| `auth.json` | (legacy, optional) same data |

You can override the server per-invocation with `-s https://other.server` or `PATCHFLY_SERVER=https://other.server` env var.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Generic error (network, server, etc.) |
| `2` | Bad usage (missing/invalid args) |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Not logged in` | Run `patchfly login` |
| `ApiException(401)` | Token expired — run `patchfly login` again |
| `Could not find an option named "--help"` | You're on an old version. Run `patchfly` installer again (see top of this README). |
| `flutter: not found` | Install Flutter and ensure `flutter` is in `PATH` |
| `unzip: not found` | `brew install unzip` (macOS) / `apt install unzip` (Linux) / install Git for Windows |
| `libapp.so not found` | Build with the correct ABI: `flutter build apk --target-platform android-arm64` |

For deeper issues, run `patchfly doctor` first.

## See also

- [`patchfly-install`](https://github.com/fatmuh/patchfly-install) — one-line installer
- [`patchfly-updater`](https://github.com/fatmuh/patchfly-updater) — Rust native engine
- [Server docs](../docs/) — running your own Patchfly server
- [SDK docs](../sdk/) — embedding Patchfly in your Flutter app
