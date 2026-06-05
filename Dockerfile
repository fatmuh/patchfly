# Patchfly server — production image.
#
# This image is built and pushed to GHCR by .github/workflows/build-ghcr.yml,
# then pulled by Dokploy.
#
# Dokploy handles HTTPS, the Postgres database, and the reverse proxy.
# The image itself is just the server process.

# --- Build stage ---
FROM dart:stable AS build

WORKDIR /build

# Cache dependencies. We deliberately don't copy the lockfile —
# `dart pub get` re-resolves against the same Dart SDK version
# (from `dart:stable`) for reproducible builds.
COPY server/pubspec.yaml /build/pubspec.yaml
RUN cd /build && dart pub get

# Build the executable
COPY server/ /build/
RUN dart compile exe bin/server.dart -o bin/server

# --- Runtime stage ---
FROM debian:bookworm-slim

# CA certificates for HTTPS calls (S3 SDK does HTTPS)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Run as non-root
RUN groupadd --system --gid 1001 patchfly && \
    useradd --system --uid 1001 --gid patchfly --home /app --shell /usr/sbin/nologin patchfly

WORKDIR /app

# Copy the compiled binary
COPY --from=build /build/bin/server /app/server

# Copy schema.sql so the operator can apply it manually if needed
COPY --from=build /build/lib/db/schema.sql /app/schema.sql

# Storage volume (only used when STORAGE_BACKEND=local)
RUN mkdir -p /var/patchfly/storage && \
    chown -R patchfly:patchfly /var/patchfly/storage

ENV PATCHFLY_ENV=production \
    PATCHFLY_HOST=0.0.0.0 \
    PATCHFLY_PORT=8080 \
    STORAGE_PATH=/var/patchfly/storage

VOLUME ["/var/patchfly/storage"]
EXPOSE 8080

USER patchfly

# Health check uses the /health endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/server"]
