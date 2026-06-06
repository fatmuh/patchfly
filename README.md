# Patchfly

**Code push / OTA update server untuk Flutter** — managed cloud service, alternatif Shorebird.

> **Upstream:** Patchfly is a fork of [Shorebird](https://github.com/shorebirdtech/shorebird) by Shorebird Labs, Inc. The entire server, CLI, and SDK are derived from Shorebird's codebase, distributed under the same dual MIT + Apache 2.0 license. See [License](#license) below.

Push perubahan Dart code ke Flutter app yang sudah live di Play Store **tanpa** rilis APK baru.

## Install CLI (one-liner)

### macOS / Linux

```bash
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.sh -sSf | bash
```

### Windows (PowerShell)

```powershell
Set-ExecutionPolicy RemoteSigned -scope CurrentUser
iwr -UseBasicParsing 'https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.ps1'|iex
```

Install location: `~/.patchfly/bin/patchfly` (Unix) atau `%USERPROFILE%\.patchfly\bin\patchfly.exe` (Windows).

Lihat [`fatmuh/patchfly-install`](https://github.com/fatmuh/patchfly-install) untuk opsi lanjutan (versi spesifik, custom install path, dst).

## Kenapa Patchfly?

- 🏠 **Self-hosted** — data & snapshot di VPS sendiri, bukan third-party
- 💰 **Komersial** — bisa di-resell ke tim / perusahaan lain (multi-tenant)
- 🎯 **Android-first** — iOS menyusul
- 🔒 **Signed patches** — setiap patch ditandatangani, app verify sebelum apply
- 📊 **Staged rollout** — rollout 1% → 10% → 100% + kill switch
- ☁️ **S3-compatible storage** — R2 / B2 / S3 / MinIO / DO Spaces
- 📉 **Differential patches** — pakai bsdiff, transfer delta bukan full snapshot

## Arsitektur Singkat

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│ Flutter App │────▶│  Patchfly   │────▶│   Storage    │
│  (patchfly  │◀────│   Server    │◀────│  (snapshot   │
│   SDK)      │     │  (REST API) │     │   files)     │
└─────────────┘     └─────────────┘     └──────────────┘
       ▲                                       ▲
       │                                       │
       │            ┌─────────────┐            │
       └────────────│     CLI     │────────────┘
                    │  patchfly   │
                    │  (build &   │
                    │   upload)   │
                    └─────────────┘
```

## Komponen

| Folder      | Bahasa        | Fungsi                                           |
| ----------- | ------------- | ------------------------------------------------ |
| `server/`   | Dart + Shelf  | REST API, auth, distribusi patch                 |
| `cli/`      | Dart          | Tooling developer: build, upload, promote patch |
| `sdk/`      | Dart/Flutter  | Package yang di-embed ke app user                |
| `docker/`   | Docker Compose| Deployment stack (server + Postgres + Nginx)     |
| `docs/`     | Markdown      | Setup, deployment, cara kerja teknis             |

## Quick Start

```bash
# 1. Clone & setup
git clone <repo> patchfly && cd patchfly
cp .env.example .env

# 2. Jalankan server + DB
docker compose up -d

# 3. Install CLI
cd cli && dart pub get
dart run bin/patchfly.dart --help

# 4. Register & login
patchfly register --email kamu@email.com
patchfly login

# 5. Di project Flutter user, tambahkan SDK & build patch
patchfly init
patchfly patch
```

Lihat [`docs/QUICKSTART.md`](docs/QUICKSTART.md) untuk langkah detail.

## Status

🚧 **MVP development** — backend, CLI, SDK sudah jalan. Lihat [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Deployment

- **Dokploy** (recommended) — push to GitHub, GHCR builds image, Dokploy pulls. See [`docs/DOKPLOY.md`](docs/DOKPLOY.md).
- **Plain Docker** — `docker compose up -d`
- **Bare metal** — `cd server && dart compile && ./bin/server`

## Lisensi

This project is a derivative work of [Shorebird](https://github.com/shorebirdtech/shorebird) and is distributed under the same dual license:

- **[MIT License](LICENSE-MIT)** — Copyright (c) 2024 Shorebird Labs, Inc. and Patchfly contributors
- **[Apache License 2.0](LICENSE-APACHE)** — Copyright (c) 2024 Shorebird Labs, Inc. and Patchfly contributors

You may use, modify, and distribute Patchfly under either license, at your option. The full upstream Shorebird license texts and copyright notices are preserved verbatim in `LICENSE-MIT` and `LICENSE-APACHE`. A summary of the changes from upstream is in [`NOTICE`](NOTICE).

The original Shorebird project lives at <https://github.com/shorebirdtech/shorebird> and is Copyright Shorebird Labs, Inc. and its contributors. Patchfly is not affiliated with, endorsed by, or sponsored by Shorebird Labs, Inc.

If you distribute Patchfly (or a modified version of it) in source or binary form, you must:

1. Retain `LICENSE-MIT` and `LICENSE-APACHE` from this repository.
2. Retain the upstream Shorebird copyright notice in every source file that was adapted from Shorebird.
3. Include a copy of the [`NOTICE`](NOTICE) file with any substantial distribution.
4. Mark any modified files (per Apache 2.0 Section 4(b)).

Commercial licensing, dual-licensing, or relicensing requests: <fatmuhdev@gmail.com>.
