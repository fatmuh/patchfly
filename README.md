# Patchfly

**Code push / OTA update server untuk Flutter** — self-hosted, komersial, alternatif Shorebird.

Push perubahan Dart code ke Flutter app yang sudah live di Play Store **tanpa** rilis APK baru.

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

Proprietary / TBD (komersial). Hubungi owner untuk lisensi.
