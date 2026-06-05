# Deploying Patchfly to Dokploy

This guide assumes you:
- Have a VPS with Dokploy installed
- Have a GitHub repo with this code pushed
- Have a domain (e.g. `api.patchfly.dev`) pointing at the VPS

The flow:
```
your code ─push─> GitHub ─> GHCR (workflow builds image)
                                    │
                                    ▼
                            Dokploy pulls image
                                    │
                                    ▼
                              Patchfly runs
```

Dokploy handles the database, HTTPS, and reverse proxy. We just push the server image.

---

## 1. Push to GitHub

If you haven't already:

```bash
cd D:/Personal/patchfly
git init
git add .
git commit -m "Initial Patchfly MVP"
gh repo create patchfly --private --source=. --remote=origin --push
# or: create the repo on github.com then:
#   git remote add origin git@github.com:fatmuh/patchfly.git
#   git push -u origin master
```

The GitHub Actions workflow (`.github/workflows/build-ghcr.yml`) triggers automatically on `master`. Watch the Actions tab — it should take ~3-5 minutes.

The image ends up at: `ghcr.io/fatmuh/patchfly:latest`

**Make the package public** (or Dokploy needs a GHCR login):
1. On GitHub: click your avatar → Packages → `patchfly` → Package settings
2. Change visibility to **Public** (or add Dokploy's service account as a collaborator)

Public is fine for a closed-source self-host because the image contains no secrets.

---

## 2. Create the Postgres database in Dokploy

1. Open Dokploy → your project → **Database** → **Create**
2. Pick **PostgreSQL 16**
3. Database name: `patchfly`
4. Username: `patchfly`
5. Set a strong password → **Save**
6. Copy the **Internal Connection String** — it'll look like:
   `postgres://patchfly:<password>@patchfly-postgres:5432/patchfly`

You'll use this as `DATABASE_URL` in the next step.

---

## 3. Generate the signing keypair

Patches are signed with Ed25519. Generate once, keep these safe — losing the private key invalidates all future patches.

```bash
cd server
dart pub get
dart run tool/gen_signing_keys.dart
```

Output:
```
Public key:  aBc123...64hexchars
Private key: dEf456...128hexchars
```

Copy both.

---

## 4. Create the Service in Dokploy

1. Dokploy → your project → **Service** → **Create**
2. **Source**: Docker Image
3. **Docker Image**: `ghcr.io/fatmuh/patchfly:latest`
4. **Port**: `8080`
5. **Healthcheck path**: `/health`
6. **Volume mount** (only if `STORAGE_BACKEND=local`):
   - Container path: `/var/patchfly/storage`
   - Host path: `/var/lib/dokploy/patchfly-storage`
7. **Env vars** (paste these, replace `<...>` with real values):

```env
PATCHFLY_ENV=production
PATCHFLY_HOST=0.0.0.0
PATCHFLY_PORT=8080
PATCHFLY_BASE_URL=https://api.patchfly.dev
DATABASE_URL=postgres://patchfly:<db-password>@<dokploy-postgres-host>:5432/patchfly
DATABASE_SSL_MODE=disable
JWT_SECRET=<openssl rand -hex 64>
JWT_EXPIRY_HOURS=720
STORAGE_BACKEND=s3
S3_BUCKET=patchfly-patches
S3_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
S3_REGION=auto
S3_ACCESS_KEY=<r2-token>
S3_SECRET_KEY=<r2-secret>
S3_USE_SSL=true
S3_AUTO_CREATE_BUCKET=true
S3_PUBLIC_URL=
PATCH_SIGNING_PUBLIC_KEY=<from step 3>
PATCH_SIGNING_PRIVATE_KEY=<from step 3>
CORS_ORIGINS=https://api.patchfly.dev
LOG_LEVEL=info
MAX_PATCH_SIZE_MB=200
```

8. **Deploy**

---

## 5. Map a domain

1. Dokploy → Service → **Domains** → **Add**
2. Host: `api.patchfly.dev`
3. Service port: `8080`
4. **Enable HTTPS** — Dokploy auto-provisions Let's Encrypt

After DNS propagates, `https://api.patchfly.dev/health` should return:
```json
{"status":"ok","service":"patchfly"}
```

---

## 6. Database schema (automatic)

The server auto-applies `lib/db/schema.sql` on first startup. You don't need to
run anything — just make sure the database exists and `DATABASE_URL` is correct.
The Docker image ships `schema.sql` at `/app/schema.sql`.

To disable auto-migration (e.g. if you use Flyway or sqitch externally), set
`RUN_MIGRATIONS=false`. The schema is idempotent so it's safe to leave enabled.

---

## 7. Smoke test

```bash
# 1. Register
curl -X POST https://api.patchfly.dev/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"strongpassword","name":"Admin"}'

# 2. Login
TOKEN=$(curl -s -X POST https://api.patchfly.dev/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"strongpassword"}' \
  | grep -oE '"token":"[^"]+"' | cut -d'"' -f4)

# 3. Who am I
curl https://api.patchfly.dev/api/v1/auth/whoami \
  -H "Authorization: Bearer $TOKEN"
```

Full end-to-end test: `make smoke` (after exporting `PATCHFLY_BASE_URL`).

---

## 8. Install the CLI on your dev machine

```bash
cd cli
dart pub global activate --source path .
patchfly init
# follow prompts — point at https://api.patchfly.dev
patchfly login
patchfly apps create my-app
# ... done
```

---

## Storage backend options

The image supports two storage backends. Pick one and set `STORAGE_BACKEND` accordingly.

### Option A: S3-compatible (recommended for production)

Works with:
- **Cloudflare R2** — free egress, $0.015/GB/mo storage
- **Backblaze B2** — $0.006/GB/mo, $0.01/GB egress
- **AWS S3** — the default
- **MinIO** — self-hostable
- **Wasabi / DigitalOcean Spaces** — both work

Set `STORAGE_BACKEND=s3` and the `S3_*` env vars.

#### Cloudflare R2 setup

1. Cloudflare dashboard → R2 → Create bucket: `patchfly-patches`
2. R2 → Manage R2 API Tokens → Create API token with **Object Read & Write** scoped to that bucket
3. Note the **Account ID** (used in `S3_ENDPOINT`)
4. R2 endpoint format: `https://<accountid>.r2.cloudflarestorage.com`
5. `S3_REGION=auto` (R2's magic value)

#### Public CDN (optional)

For faster downloads and to reduce load on Patchfly, set up a CDN in front of your bucket:
- Cloudflare R2 has a built-in public bucket URL — set `S3_PUBLIC_URL` to it
- For S3, put CloudFront/Cloudflare in front and use the CDN URL

The SDK will download patches directly from the CDN. Patchfly only signs the manifest.

### Option B: Local filesystem (dev / single-server)

Set `STORAGE_BACKEND=local`. Patches go in `/var/patchfly/storage` inside the container. **Mount a Dokploy volume** to persist across redeploys.

Downside: you can't scale horizontally. Each new server needs the same volume (use shared storage like NFS, or just stick to one replica).

---

## Updating the server

```bash
git commit -am "fix: ..."
git push origin master
# GitHub Actions rebuilds the image automatically
# In Dokploy: Service → Redeploy (or enable auto-deploy on push)
```

To auto-deploy: Dokploy Service → **Source** → **Watch** for `master` branch.

---

## Backup

The only stateful data is:
1. **Postgres** (users, apps, releases, patch metadata, event log)
2. **S3 bucket** (the actual `libapp.so` files)

Dokploy's built-in database backup works for #1. For #2, enable versioning on the bucket (R2/S3 both support this) or use a lifecycle rule.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `S3 bucket does not exist` | Set `S3_AUTO_CREATE_BUCKET=true` or create manually |
| `JWT_SECRET must be set in production` | Set it in Dokploy env vars (no default in prod) |
| Health check fails | `docker exec -it <container> curl localhost:8080/health` — usually means DB unreachable |
| SDK gets 401 on check | `X-Patchfly-SDK-Key` header missing or `pfk_` key rotated |
| Patch download slow | Set up CDN via `S3_PUBLIC_URL` |

---

## Cost reference (rough)

A typical small team setup (Cloudflare R2):
- VPS for Dokploy: $5-12/mo (Hetzner, DO)
- R2 storage: ~$0.15/mo per 1000 patches
- R2 egress: **$0** (R2's killer feature)
- GitHub Actions: free for public repos, 2000 min/mo for private
- Domain: $10/yr

Total: **< $15/mo** for a self-hosted Shorebird replacement.
