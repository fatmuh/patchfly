# Deployment

Production deployment guide for the Patchfly server on a VPS.

## Minimum requirements

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 1 vCPU | 2 vCPU |
| RAM | 1 GB | 2 GB |
| Disk | 20 GB | 100 GB+ (scales with patches) |
| Bandwidth | 100 GB/mo | 1 TB/mo |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

For 10,000 MAU (monthly active users) and ~50 MB patches, expect
~500 GB of bandwidth per month from patch downloads.

## Initial setup

```bash
# 1. Update the system
sudo apt update && sudo apt upgrade -y

# 2. Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# log out and back in

# 3. Install certbot for SSL
sudo apt install -y certbot

# 4. Get a cert
sudo certbot certonly --nginx -d api.patchfly.dev
# (or use --standalone if you don't have nginx yet)
```

## Configure environment

```bash
git clone <your-patchfly-fork-or-publish-url> /opt/patchfly
cd /opt/patchfly

# Generate secrets
export POSTGRES_PASSWORD=$(openssl rand -hex 32)
export JWT_SECRET=$(openssl rand -hex 64)

# Generate signing keys
cd server
dart run tool/gen_signing_keys.dart > /tmp/signing_keys.env
cat /tmp/signing_keys.env >> /opt/patchfly/.env
cd ..

cat > .env <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
PATCHFLY_BASE_URL=https://api.patchfly.dev
PATCHFLY_ENV=production
EOF

# Source the signing keys
cat /tmp/signing_keys.env >> .env
rm /tmp/signing_keys.env
```

## Configure nginx

```bash
sudo mkdir -p /opt/patchfly/docker/ssl
sudo cp /etc/letsencrypt/live/api.patchfly.dev/fullchain.pem /opt/patchfly/docker/ssl/
sudo cp /etc/letsencrypt/live/api.patchfly.dev/privkey.pem /opt/patchfly/docker/ssl/
```

## Start the stack

```bash
docker compose up -d
docker compose logs -f
```

Verify health:
```bash
curl https://api.patchfly.dev/health
# {"status":"ok","service":"patchfly","version":"0.1.0"}
```

## Backups

The patch files in `/var/patchfly/storage` are the most important
data. Back them up regularly:

```bash
# Add to /etc/cron.daily/patchfly-backup:
#!/bin/bash
docker compose -f /opt/patchfly/docker-compose.yml exec postgres \
  pg_dump -U patchfly -Fc patchfly > /var/backups/patchfly/db-$(date +%F).dump
tar -czf /var/backups/patchfly/storage-$(date +%F).tgz /var/patchfly/storage
# Keep only 30 days
find /var/backups/patchfly -mtime +30 -delete
```

## Monitoring

For an MVP, watch:
- Disk usage (`df -h`) — patches grow
- Postgres connections (`docker compose exec postgres psql -c "SELECT count(*) FROM pg_stat_activity"`)
- Server logs (`docker compose logs -f server`)

Wire to a proper monitoring stack (Prometheus + Grafana) when you
have paying customers.

## SSL renewal

```bash
# /etc/cron.monthly/patchfly-ssl-renew
certbot renew --quiet
cp /etc/letsencrypt/live/api.patchfly.dev/fullchain.pem /opt/patchfly/docker/ssl/
cp /etc/letsencrypt/live/api.patchfly.dev/privkey.pem /opt/patchfly/docker/ssl/
docker compose -f /opt/patchfly/docker-compose.yml restart nginx
```

## Scaling considerations

### When to scale up (vertical)

- CPU > 70% sustained
- Postgres queries > 100ms
- Disk > 80% full

### When to scale out (horizontal)

- Multiple servers behind a load balancer
- BUT: patch storage must be shared (NFS, S3, MinIO cluster)
- Easy upgrade path: switch `StorageService` to S3

### Migration to S3 (future)

The `StorageService` class is the seam. To swap to S3:
1. Implement `S3StorageService implements StorageService`
2. Configure `STORAGE_BACKEND=s3` and S3 creds
3. Migrate existing files with `aws s3 sync /var/patchfly/storage s3://bucket/`
4. Restart server

## Security checklist

- [ ] SSH key-only login (disable password auth)
- [ ] Firewall: only 22, 80, 443 open
- [ ] Fail2ban enabled
- [ ] Docker running as non-root (it is by default in 20.10+)
- [ ] Postgres not exposed externally
- [ ] `.env` file permissions: `chmod 600 .env`
- [ ] JWT secret is 64+ random bytes
- [ ] Patch signing keys are 32-byte ed25519
- [ ] Backups run daily and are tested quarterly
- [ ] `PATCHFLY_ENV=production` in `.env` (catches misconfigs at boot)
