#!/usr/bin/env bash
# End-to-end smoke test. Assumes:
#   - Server is running at $PATCHFLY_SERVER (default http://localhost:8080)
#   - Database has been initialized (schema.sql applied)
#   - PATCHFLY env var can be set to override the server URL
#
# Run: ./scripts/smoke_test.sh
#
# Exits 0 on success, non-zero on any failure.

set -euo pipefail

SERVER="${PATCHFLY_SERVER:-http://localhost:8080}"
EMAIL="smoketest+$(date +%s)@example.com"
PASSWORD="smoketest-password-123"
SDK_KEY=""

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

step() { blue "▶ $*"; }
ok()   { green "✓ $*"; }
die()  { red "✗ $*"; exit 1; }

step "Health check"
HEALTH=$(curl -fsS "$SERVER/health")
echo "  $HEALTH"
[[ "$HEALTH" == *'"status":"ok"'* ]] || die "Health check failed"
ok "Server is up"

step "Register user"
REG=$(curl -fsS -X POST "$SERVER/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
TOKEN=$(echo "$REG" | python -c "import sys,json; print(json.load(sys.stdin)['token'])")
[ -n "$TOKEN" ] || die "No token in register response"
ok "Got JWT"

step "Verify login"
LOGIN=$(curl -fsS -X POST "$SERVER/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
[ -n "$LOGIN" ] || die "Login failed"
ok "Login works"

step "Create app"
APP=$(curl -fsS -X POST "$SERVER/api/v1/apps" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"slug\":\"smoke-test-$(date +%s)\",\"name\":\"Smoke Test App\",\"platform\":\"android\"}")
APP_ID=$(echo "$APP" | python -c "import sys,json; print(json.load(sys.stdin)['app']['id'])")
SDK_KEY=$(echo "$APP" | python -c "import sys,json; print(json.load(sys.stdin)['sdkKey'])")
[ -n "$APP_ID" ] || die "No app id"
[ -n "$SDK_KEY" ] || die "No SDK key"
ok "Created app $APP_ID"

step "Create release"
REL=$(curl -fsS -X POST "$SERVER/api/v1/apps/$APP_ID/releases" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"version\":\"1.0.0+1\",\"channel\":\"stable\"}")
REL_ID=$(echo "$REL" | python -c "import sys,json; print(json.load(sys.stdin)['release']['id'])")
[ -n "$REL_ID" ] || die "No release id"
ok "Created release $REL_ID"

step "Upload patch"
TMP=$(mktemp)
dd if=/dev/urandom of="$TMP" bs=1024 count=100 2>/dev/null
SHA=$(sha256sum "$TMP" | awk '{print $1}')
PATCH=$(curl -fsS -X POST "$SERVER/api/v1/releases/$REL_ID/patches" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@$TMP" \
  -F "sha256=$SHA" \
  -F "activate=true")
PATCH_ID=$(echo "$PATCH" | python -c "import sys,json; print(json.load(sys.stdin)['patch']['id'])")
[ -n "$PATCH_ID" ] || die "No patch id"
ok "Uploaded patch $PATCH_ID (sha=$SHA)"

step "SDK check"
CHECK=$(curl -fsS -X POST "$SERVER/api/v1/sdk/check" \
  -H "X-Patchfly-SDK-Key: $SDK_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"channel\":\"stable\",\"appVersion\":\"1.0.0+1\",\"deviceId\":\"smoke-test\"}")
echo "  $CHECK"
[[ "$CHECK" == *'"hasUpdate":true'* ]] || die "Check did not return update"
ok "SDK check returns the patch"

step "Download patch"
DOWNLOADED=$(curl -fsS "$SERVER/api/v1/sdk/patch/$PATCH_ID/file" \
  -H "X-Patchfly-SDK-Key: $SDK_KEY" \
  -o "$TMP.downloaded")
DLSHA=$(sha256sum "$TMP.downloaded" | awk '{print $1}')
[ "$DLSHA" = "$SHA" ] || die "Downloaded sha256 mismatch: $DLSHA != $SHA"
ok "Downloaded patch sha256 matches"

step "Verify signature header"
SIG=$(curl -fsS -I "$SERVER/api/v1/sdk/patch/$PATCH_ID/file" \
  -H "X-Patchfly-SDK-Key: $SDK_KEY" 2>&1 | grep -i "x-patchfly-signature" | awk '{print $2}' | tr -d '\r')
[ -n "$SIG" ] || die "No signature header"
ok "Signature header present: ${SIG:0:20}..."

step "Public key endpoint"
PUBKEY=$(curl -fsS "$SERVER/api/v1/sdk/public-key")
[ -n "$PUBKEY" ] || die "No public key"
ok "Public key available: $(echo $PUBKEY | python -c "import sys,json; print(json.load(sys.stdin)['publicKey'][:16])")..."

rm -f "$TMP" "$TMP.downloaded"

echo
green "═══════════════════════════════════════════"
green "  ✓ All smoke tests passed."
green "═══════════════════════════════════════════"
