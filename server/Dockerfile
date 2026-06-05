# Build stage
FROM dart:stable AS build
WORKDIR /app

# Cache dependencies
COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get

# Build
COPY . .
RUN dart compile exe bin/server.dart -o /app/bin/server

# Runtime stage
FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /app/lib/db/schema.sql /app/lib/db/schema.sql

# Storage volume
RUN mkdir -p /var/patchfly/storage
VOLUME ["/var/patchfly/storage"]

ENV PATCHFLY_ENV=production
EXPOSE 8080

ENTRYPOINT ["/app/bin/server"]
