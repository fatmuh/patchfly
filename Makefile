.PHONY: help dev server-build server-run server-test cli-install cli-test sdk-analyze docker-up docker-down docker-logs db-shell smoke clean

# --- Help ---
help:
	@echo "Patchfly — make targets:"
	@echo "  make docker-up      Start Postgres + server + nginx (Docker)"
	@echo "  make docker-down    Stop the stack"
	@echo "  make docker-logs    Tail server logs"
	@echo "  make db-shell       Open psql in the Postgres container"
	@echo "  make server-run     Run the Dart server (needs Postgres on host)"
	@echo "  make server-test    Run server tests"
	@echo "  make server-build   Compile server binary"
	@echo "  make cli-install    Install CLI from source"
	@echo "  make cli-test       Run CLI tests"
	@echo "  make sdk-analyze    Run flutter analyze on the SDK"
	@echo "  make smoke          Run end-to-end smoke test (needs server)"
	@echo "  make clean          Remove build artifacts"

# --- Docker stack ---
docker-up:
	docker compose up -d
	@echo "Server: http://localhost:8080  (or https://\$\$PATCHFLY_BASE_URL in prod)"

docker-down:
	docker compose down

docker-logs:
	docker compose logs -f server

db-shell:
	docker compose exec postgres psql -U patchfly patchfly

# --- Server (native) ---
server-run:
	cd server && dart pub get && dart run bin/server.dart

server-build:
	cd server && dart compile exe bin/server.dart -o bin/server

server-test:
	cd server && dart test

# --- CLI ---
cli-install:
	cd cli && dart pub get && dart pub global activate --source path .

cli-test:
	cd cli && dart test

# --- SDK ---
sdk-analyze:
	cd sdk && flutter analyze

# --- Smoke test (requires running server) ---
smoke:
	PATCHFLY_SERVER=$${PATCHFLY_SERVER:-http://localhost:8080} ./scripts/smoke_test.sh

# --- Cleanup ---
clean:
	rm -rf server/.dart_tool server/build server/bin/server
	rm -rf cli/.dart_tool cli/build
	rm -rf sdk/.dart_tool sdk/build sdk/.flutter-plugins sdk/.flutter-plugins-dependencies
	rm -rf sdk/example/.dart_tool sdk/example/build
	find . -name '*.iml' -delete
	find . -name '.idea' -type d -exec rm -rf {} + 2>/dev/null || true
