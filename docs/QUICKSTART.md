# Quickstart

Get Patchfly running in 15 minutes.

## 0. Prerequisites

- A Linux/macOS VPS (or just your laptop for trying it out)
- Docker + Docker Compose
- A Flutter project you want to ship updates for

## 1. Clone & configure

```bash
git clone <repo> patchfly
cd patchfly
cp .env.example .env
```

Edit `.env` and set:
- `POSTGRES_PASSWORD` (random strong password)
- `JWT_SECRET` (`openssl rand -hex 64`)
- `PATCHFLY_BASE_URL` (your public URL, e.g. `https://api.patchfly.dev`)

## 2. Start the stack

```bash
docker compose up -d
docker compose logs -f server
```

You should see "Listening on http://0.0.0.0:8080" and a successful
Postgres connection.

## 3. Set up SSL (production only)

In dev, you can hit the server on http://localhost:8080 directly.
For production, put nginx + Let's Encrypt in front.

```bash
# Get a cert
sudo certbot certonly --nginx -d api.patchfly.dev
# Copy into docker
sudo cp /etc/letsencrypt/live/api.patchfly.dev/fullchain.pem docker/ssl/
sudo cp /etc/letsencrypt/live/api.patchfly.dev/privkey.pem docker/ssl/
```

## 4. Install the CLI

```bash
cd cli
dart pub get
# Optional: install globally
dart pub global activate --source path .
```

## 5. Create an account

```bash
patchfly register
# Email: you@example.com
# Password: ********
```

## 6. Create an app

```bash
patchfly apps create --slug com.acme.myapp --name "Acme MyApp" --platform android
# ✓ App created: com.acme.myapp (uuid-here)
# SDK key (save now, you cannot see it again):
#   pfk_...
```

Save the SDK key somewhere safe — you'll embed it in your app.

## 7. In your Flutter project

```bash
cd /path/to/your_flutter_app
patchfly init
# Edit patchfly.yaml and set:
#   app.slug: com.acme.myapp

# Add the SDK
# pubspec.yaml:
#   dependencies:
#     patchfly:
#       path: /path/to/patchfly/sdk

# Initialize in main.dart
# await Patchfly.init(
#   serverUrl: 'https://api.patchfly.dev',
#   sdkKey: 'pfk_...',
#   channel: 'stable',
# );
```

See [`ANDROID_INTEGRATION.md`](ANDROID_INTEGRATION.md) for the rest of
the Android-side setup.

## 8. Create a release

```bash
patchfly releases create \
  --app com.acme.myapp \
  --version 1.0.0+1 \
  --channel stable
```

## 9. Ship a patch

Make some code changes, then:

```bash
patchfly patch
# Building Flutter APK (release)...
# Extracting libapp.so for arm64-v8a...
# libapp.so: 8.4 MB, sha256=abc...
# Uploading patch...
# ✓ Patch #1 uploaded (8.4 MB)
#   Status: ACTIVE (live for all matching devices)
```

## 10. Verify

On any device that has the app installed, restart it. The new code
should be running.

To roll back:
```bash
# List patches
patchfly releases list com.acme.myapp

# Activate an older patch
patchfly promote --app com.acme.myapp --release <rel-id> --patch 1
```

## Next steps

- Read [`ARCHITECTURE.md`](ARCHITECTURE.md) for the system design
- Read [`DEPLOYMENT.md`](DEPLOYMENT.md) for production deployment
- Read [`ANDROID_INTEGRATION.md`](ANDROID_INTEGRATION.md) for the full
  Android setup
- Read [`ROADMAP.md`](ROADMAP.md) for what's coming
