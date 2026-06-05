# Patchfly Server

REST API backend for code push / OTA updates.

## Develop

```bash
# Install deps
dart pub get

# Run locally (needs Postgres running)
DATABASE_URL=postgres://patchfly:patchfly@localhost:5432/patchfly \
  JWT_SECRET=dev-secret \
  dart run bin/server.dart
```

## Build production binary

```bash
dart compile exe bin/server.dart -o bin/server
./bin/server
```

## Docker

```bash
docker build -t patchfly-server .
docker run --rm -p 8080:8080 \
  -e DATABASE_URL=... \
  -e JWT_SECRET=... \
  patchfly-server
```

## API surface

See [`docs/QUICKSTART.md`](../docs/QUICKSTART.md) and the routes in
`lib/routes/`. All endpoints are JSON. Auth is via Bearer token
(JWT or API key) for `/api/v1/keys`, `/api/v1/apps`, and below; via
`X-Patchfly-SDK-Key` header for `/api/v1/sdk/*`.

## Generating signing keys

```bash
dart run tool/gen_signing_keys.dart
# Copy the output to your .env as PATCH_SIGNING_PUBLIC_KEY and PATCH_SIGNING_PRIVATE_KEY
```

> **Production:** Use a real ed25519 library, not the throwaway
> generator. The tool prints placeholder bytes. Replace with a
> library-generated key pair before going live.

## Layout

```
lib/
  config.dart            Environment config
  main.dart              Wire up & serve
  db/
    database.dart        Postgres pool
    schema.sql           DB schema (loaded on first start)
  middleware/
    auth_middleware.dart JWT / API key auth
    error_middleware.dart Convert exceptions to JSON
  models/                Data classes
  routes/                HTTP handlers
  services/              Business logic
  utils/                 JWT, hash, signing, json helpers

tool/
  gen_signing_keys.dart  Generate ed25519 keypair (dev only)
```
