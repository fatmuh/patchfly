#!/usr/bin/env bash
# Local development setup.
# Run from the repo root: ./scripts/dev.sh

set -euo pipefail

# 1. Make sure .env exists
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example. Edit it before going to production."
fi

# 2. Start the stack
docker compose up -d

# 3. Wait for Postgres
echo "Waiting for Postgres..."
for i in {1..30}; do
  if docker compose exec -T postgres pg_isready -U patchfly >/dev/null 2>&1; then
    echo "Postgres is up."
    break
  fi
  sleep 1
done

# 4. Wait for server
echo "Waiting for server..."
for i in {1..30}; do
  if curl -fsS http://localhost:8080/health >/dev/null 2>&1; then
    echo "Server is up."
    break
  fi
  sleep 1
done

# 5. Show summary
cat <<EOF

=========================================
  Patchfly dev stack is up.

  Server:    http://localhost:8080
  Postgres:  localhost:5432 (user: patchfly, db: patchfly)
  Storage:   ./storage (mounted into container)

  Next steps:
    cd cli && dart pub get
    dart pub global activate --source path .
    patchfly register
    patchfly apps create --slug com.example.app --name "My App"

  Or use the example SDK app:
    cd sdk/example
    flutter pub get
    flutter run

=========================================
EOF
