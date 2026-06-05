-- Patchfly database schema.
-- Loaded on first Postgres startup (docker-entrypoint-initdb.d).

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================
-- USERS
-- =============================================================
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    name            TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- =============================================================
-- API KEYS (for CLI auth)
-- =============================================================
CREATE TABLE IF NOT EXISTS api_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    key_hash        TEXT UNIQUE NOT NULL,    -- sha256 of the key
    key_prefix      TEXT NOT NULL,           -- first 8 chars for display
    last_used_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_keys_user ON api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON api_keys(key_hash);

-- =============================================================
-- APPS (each customer app that uses Patchfly)
-- =============================================================
CREATE TABLE IF NOT EXISTS apps (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    slug            TEXT UNIQUE NOT NULL,        -- e.g. "com.acme.myapp"
    name            TEXT NOT NULL,
    platform        TEXT NOT NULL DEFAULT 'android', -- android / ios
    -- SDK API key for this app. Used by mobile clients.
    sdk_key_hash    TEXT UNIQUE NOT NULL,
    sdk_key_prefix  TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_apps_owner ON apps(owner_id);

-- =============================================================
-- CHANNELS (staged rollout groups: stable / beta / internal)
-- =============================================================
CREATE TABLE IF NOT EXISTS channels (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_id          UUID NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,            -- stable, beta, alpha, internal
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(app_id, name)
);

-- =============================================================
-- RELEASES (a "version" of an app, tied to a channel)
-- =============================================================
CREATE TABLE IF NOT EXISTS releases (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_id          UUID NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
    channel_id      UUID NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    version         TEXT NOT NULL,            -- e.g. "1.4.2+15"
    -- Active = currently the head release on this channel.
    is_active       BOOLEAN NOT NULL DEFAULT false,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(app_id, version)
);

CREATE INDEX IF NOT EXISTS idx_releases_app ON releases(app_id);
CREATE INDEX IF NOT EXISTS idx_releases_active ON releases(app_id, is_active) WHERE is_active = true;

-- =============================================================
-- PATCHES (the actual code update = AOT snapshot file)
-- =============================================================
CREATE TABLE IF NOT EXISTS patches (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    release_id          UUID NOT NULL REFERENCES releases(id) ON DELETE CASCADE,
    patch_number        INT NOT NULL,            -- monotonic per release, starts at 1
    -- File storage
    file_path           TEXT NOT NULL,           -- relative to STORAGE_PATH
    file_size_bytes     BIGINT NOT NULL,
    sha256_hash         TEXT NOT NULL,
    -- Cryptographic signature over sha256_hash (hex, ed25519)
    signature           TEXT NOT NULL,
    -- Targeting
    min_app_version     TEXT,                    -- app must be >= this
    max_app_version     TEXT,                    -- app must be <= this (optional cap)
    -- Rollout (0-100)
    rollout_percent     INT NOT NULL DEFAULT 100 CHECK (rollout_percent BETWEEN 0 AND 100),
    -- State
    is_active           BOOLEAN NOT NULL DEFAULT false,
    -- For differential patches, reference base patch
    base_patch_id       UUID REFERENCES patches(id) ON DELETE SET NULL,
    is_delta            BOOLEAN NOT NULL DEFAULT false,
    -- Telemetry
    download_count      BIGINT NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(release_id, patch_number)
);

CREATE INDEX IF NOT EXISTS idx_patches_release ON patches(release_id);
CREATE INDEX IF NOT EXISTS idx_patches_active ON patches(release_id, is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_patches_created ON patches(release_id, created_at DESC);

-- =============================================================
-- PATCH EVENTS (audit / analytics)
-- =============================================================
CREATE TABLE IF NOT EXISTS patch_events (
    id              BIGSERIAL PRIMARY KEY,
    patch_id        UUID REFERENCES patches(id) ON DELETE CASCADE,
    app_id          UUID NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL,   -- check, download, apply, error
    app_version     TEXT,            -- user app version
    device_id       TEXT,
    error_message   TEXT,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_app_time ON patch_events(app_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_patch ON patch_events(patch_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON patch_events(event_type, created_at DESC);

-- =============================================================
-- Trigger: updated_at maintenance
-- =============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated ON users;
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_apps_updated ON apps;
CREATE TRIGGER trg_apps_updated BEFORE UPDATE ON apps
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- ASSETS (config/asset OTA per app)
-- =============================================================
CREATE TABLE IF NOT EXISTS assets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_id          UUID NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
    version         INTEGER NOT NULL,
    storage_key     TEXT NOT NULL,            -- path in storage backend
    size_bytes      BIGINT NOT NULL,
    sha256          TEXT NOT NULL,
    changelog       TEXT,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (app_id, version)
);

CREATE INDEX IF NOT EXISTS idx_assets_app_version ON assets(app_id, version DESC);
