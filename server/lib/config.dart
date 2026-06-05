// Application configuration loaded from environment.
//
// All config is centralized here. Read once at startup, injected into
// services that need it. Never read process.env() outside this file.

import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:logging/logging.dart';

class AppConfig {
  final String host;
  final int port;
  final String baseUrl;
  final String env;
  final String databaseUrl;
  final int databaseMaxConnections;
  final String databaseSslMode;
  final String jwtSecret;
  final int jwtExpiryHours;
  final String storageBackend;
  final String storagePath;
  final int maxPatchSizeMb;
  final bool runMigrations;
  final String schemaPath;
  final String? s3Bucket;
  final String? s3Endpoint;
  final String? s3Region;
  final String? s3AccessKey;
  final String? s3SecretKey;
  final bool s3UseSsl;
  final bool s3AutoCreateBucket;
  final String? s3PublicUrl;
  final String? signingPublicKey;
  final String? signingPrivateKey;
  final String corsOrigins;
  final String logLevel;

  AppConfig._({
    required this.host,
    required this.port,
    required this.baseUrl,
    required this.env,
    required this.databaseUrl,
    required this.databaseMaxConnections,
    required this.databaseSslMode,
    required this.jwtSecret,
    required this.jwtExpiryHours,
    required this.storageBackend,
    required this.storagePath,
    required this.maxPatchSizeMb,
    required this.runMigrations,
    required this.schemaPath,
    required this.s3Bucket,
    required this.s3Endpoint,
    required this.s3Region,
    required this.s3AccessKey,
    required this.s3SecretKey,
    required this.s3UseSsl,
    required this.s3AutoCreateBucket,
    required this.s3PublicUrl,
    required this.signingPublicKey,
    required this.signingPrivateKey,
    required this.corsOrigins,
    required this.logLevel,
  });

  static AppConfig load() {
    try {
      DotEnv(includePlatformEnvironment: true).load(['.env']);
    } catch (_) {}

    String env(String key, [String fallback = '']) {
      // Try the requested key first (e.g. PATCHFLY_BASE_URL).
      final v = Platform.environment[key];
      if (v != null && v.isNotEmpty) return v;
      // Backward compat: also try the Pultflut-prefixed version
      // (e.g. PULTFLUT_BASE_URL) so existing deployments don't break.
      if (key.startsWith('PATCHFLY_')) {
        final legacy = Platform.environment['PULTFLUT_${key.substring(9)}'];
        if (legacy != null && legacy.isNotEmpty) return legacy;
      }
      return fallback;
    }

    String? envOpt(String key) {
      final v = Platform.environment[key];
      if (v == null || v.isEmpty) {
        if (key.startsWith('PATCHFLY_')) {
          final legacy = Platform.environment['PULTFLUT_${key.substring(9)}'];
          if (legacy != null && legacy.isNotEmpty) return legacy;
        }
        return null;
      }
      return v;
    }

    int envInt(String key, int fallback) {
      final v = Platform.environment[key];
      if (v == null || v.isEmpty) {
        if (key.startsWith('PATCHFLY_')) {
          final legacy = Platform.environment['PULTFLUT_${key.substring(9)}'];
          if (legacy != null && legacy.isNotEmpty) {
            return int.tryParse(legacy) ?? fallback;
          }
        }
        return fallback;
      }
      return int.tryParse(v) ?? fallback;
    }

    bool envBool(String key, bool fallback) {
      final v = Platform.environment[key];
      if (v == null || v.isEmpty) {
        if (key.startsWith('PATCHFLY_')) {
          final legacy = Platform.environment['PULTFLUT_${key.substring(9)}'];
          if (legacy != null && legacy.isNotEmpty) {
            return legacy.toLowerCase() == 'true' || legacy == '1';
          }
        }
        return fallback;
      }
      return v.toLowerCase() == 'true' || v == '1';
    }

    // Resolve JWT_SECRET: prefer real env, fall back to dev only outside prod.
    // NB: cannot use a default parameter for this — Dart evaluates default
    // arguments unconditionally, so a throwing default would fire even when
    // the env var is set.
    final isProd = env('PATCHFLY_ENV', 'development') == 'production';
    final jwtSecretOrNull = envOpt('JWT_SECRET');
    final jwtSecret = (jwtSecretOrNull == null || jwtSecretOrNull.isEmpty)
        ? (isProd
            ? () {
                _printMissingJwtSecretDiagnosis();
                throw StateError('JWT_SECRET must be set in production');
              }()
            : 'dev-secret-DO-NOT-USE-IN-PRODUCTION')
        : jwtSecretOrNull;

    final config = AppConfig._(
      host: env('PATCHFLY_HOST', '0.0.0.0'),
      port: envInt('PATCHFLY_PORT', 8080),
      baseUrl: env('PATCHFLY_BASE_URL', 'http://localhost:8080'),
      env: env('PATCHFLY_ENV', 'development'),
      databaseUrl: env(
        'DATABASE_URL',
        'postgres://patchfly:patchfly@localhost:5432/patchfly',
      ),
      databaseMaxConnections: envInt('DATABASE_MAX_CONNECTIONS', 10),
      databaseSslMode: env('DATABASE_SSL_MODE', 'disable'),
      jwtSecret: jwtSecret,
      jwtExpiryHours: envInt('JWT_EXPIRY_HOURS', 720),
      storageBackend: env('STORAGE_BACKEND', 'local'),
      storagePath: env('STORAGE_PATH', './storage'),
      maxPatchSizeMb: envInt('MAX_PATCH_SIZE_MB', 200),
      runMigrations: envBool('RUN_MIGRATIONS', true),
      schemaPath: env('SCHEMA_PATH', ''),
      s3Bucket: envOpt('S3_BUCKET'),
      s3Endpoint: envOpt('S3_ENDPOINT'),
      s3Region: envOpt('S3_REGION'),
      s3AccessKey: envOpt('S3_ACCESS_KEY'),
      s3SecretKey: envOpt('S3_SECRET_KEY'),
      s3UseSsl: envBool('S3_USE_SSL', true),
      s3AutoCreateBucket: envBool('S3_AUTO_CREATE_BUCKET', true),
      s3PublicUrl: envOpt('S3_PUBLIC_URL'),
      signingPublicKey: envOpt('PATCH_SIGNING_PUBLIC_KEY'),
      signingPrivateKey: envOpt('PATCH_SIGNING_PRIVATE_KEY'),
      corsOrigins: env('CORS_ORIGINS', '*'),
      logLevel: env('LOG_LEVEL', 'info'),
    );

    _validate(config);
    return config;
  }

  static void _printMissingJwtSecretDiagnosis() {
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('================================================================');
    // ignore: avoid_print
    print('FATAL: JWT_SECRET is missing in production mode.');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('Process env vars that start with PATCHFLY_, JWT_, DATABASE_,');
    // ignore: avoid_print
    print('S3_, STORAGE_, CORS_, LOG_, PATCH_, SCHEMA_:');
    for (final entry in Platform.environment.entries) {
      final k = entry.key;
      if (RegExp(
              r'^(PATCHFLY_|JWT_|DATABASE_|S3_|STORAGE_|CORS_|LOG_|PATCH_|SCHEMA_)')
          .hasMatch(k)) {
        // ignore: avoid_print
        print('  $k = (${entry.value.length} chars)');
      }
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('In Dokploy: Service -> Environment -> add JWT_SECRET=<value>');
    // ignore: avoid_print
    print('Generate with: openssl rand -hex 64');
    // ignore: avoid_print
    print('Then: Redeploy the service.');
    // ignore: avoid_print
    print('================================================================');
    // ignore: avoid_print
    print('');
  }

  static void _validate(AppConfig c) {
    if (c.baseUrl.endsWith('/')) {
      throw StateError('PATCHFLY_BASE_URL must not end with /');
    }
    if (c.maxPatchSizeMb <= 0) {
      throw StateError('MAX_PATCH_SIZE_MB must be > 0');
    }
    if (c.storageBackend.toLowerCase().startsWith('s3')) {
      if (c.s3Bucket == null || c.s3Bucket!.isEmpty) {
        throw StateError('S3_BUCKET is required when STORAGE_BACKEND=s3');
      }
    }
  }

  bool get isDev => env == 'development';
  bool get isProd => env == 'production';
}

void setupLogging(String level) {
  Logger.root.level = _parseLogLevel(level);
  Logger.root.onRecord.listen((rec) {
    final ts = rec.time.toIso8601String();
    final lvl = rec.level.name.toUpperCase().padRight(7);
    // ignore: avoid_print
    print('$ts [$lvl] ${rec.loggerName}: ${rec.message}'
        '${rec.error != null ? ' ERROR: ${rec.error}' : ''}');
  });
}

Level _parseLogLevel(String s) {
  switch (s.toLowerCase()) {
    case 'all':
      return Level.ALL;
    case 'fine':
    case 'debug':
      return Level.FINE;
    case 'info':
      return Level.INFO;
    case 'warning':
    case 'warn':
      return Level.WARNING;
    case 'error':
      return Level.SEVERE;
    case 'off':
      return Level.OFF;
    default:
      return Level.INFO;
  }
}
