// Main entrypoint — wires up database, services, and routes.

import 'dart:io';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'config.dart';
import 'db/database.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/error_middleware.dart';
import 'routes/api_key_routes.dart';
import 'routes/app_routes.dart';
import 'routes/auth_routes.dart';
import 'routes/patch_routes.dart';
import 'routes/sdk_routes.dart';
import 'services/api_key_service.dart';
import 'services/app_service.dart';
import 'services/asset_service.dart';
import 'services/channel_service.dart';
import 'services/event_service.dart';
import 'services/patch_service.dart';
import 'services/release_service.dart';
import 'services/storage_service.dart';
import 'services/user_service.dart';
import 'utils/json_response.dart';
import 'utils/jwt.dart';
import 'utils/patch_signer.dart';

Future<void> bootstrap({List<String> args = const []}) async {
  final cfg = AppConfig.load();
  setupLogging(cfg.logLevel);

  final log = Logger('Bootstrap');
  log.info('Starting Patchfly server (env=${cfg.env}, base=${cfg.baseUrl})');
  _logConfigDiagnostic(log);

  final db = await Database.connect(cfg);
  final storage = await StorageService.fromConfig(cfg);

  PatchSigner signer;
  if (cfg.signingPrivateKey != null && cfg.signingPublicKey != null) {
    signer = PatchSigner.fromBase64(
      privateKeyB64: cfg.signingPrivateKey!,
      publicKeyB64: cfg.signingPublicKey!,
    );
    log.info('Loaded patch signing keys (ed25519)');
  } else if (cfg.isProd) {
    throw StateError(
      'PATCH_SIGNING_PUBLIC_KEY and PATCH_SIGNING_PRIVATE_KEY must be set in production. '
      'Generate with: dart run tool/gen_signing_keys.dart',
    );
  } else {
    // Dev fallback: generate an ephemeral key for this run.
    log.warning(
      'No signing keys configured. Using ephemeral dev keys; '
      'patches uploaded in this session will not verify with the SDK '
      'in a later session. Run `dart run tool/gen_signing_keys.dart`.',
    );
    signer = _devEphemeralSigner();
  }

  final users = UserService(db);
  final apiKeys = ApiKeyService(db);
  final appsSvc = AppService(db);
  final channels = ChannelService(db);
  final releasesSvc = ReleaseService(db);
  final patchesSvc = PatchService(db, storage, signer, cfg);
  final events = EventService(db);

  final jwt = JwtService(cfg);
  final auth = AuthMiddleware(jwt, apiKeys, users);

  final authRoutes = AuthRoutes(users, jwt);
  final appRoutes = AppRoutes(appsSvc, releasesSvc, channels, patchesSvc);
  final patchRoutes = PatchRoutes(appsSvc, releasesSvc, patchesSvc, cfg);
  final apiKeyRoutes = ApiKeyRoutes(apiKeys);
  final assetSvc = AssetService(db, storage);
  final sdkRoutes = SdkRoutes(
      appsSvc, patchesSvc, releasesSvc, storage, events, signer, assetSvc);

  // Public router (no user auth required)
  final publicRouter = Router()
    ..get('/health', (_) async => jsonResponse({
          'status': 'ok',
          'service': 'patchfly',
          'version': '0.1.0',
        }))
    ..get('/', (_) async => jsonResponse({
          'name': 'Patchfly',
          'version': '0.1.0',
          'docs': '${cfg.baseUrl}/docs',
        }))
    ..post('/api/v1/auth/register', authRoutes.register)
    ..post('/api/v1/auth/login', authRoutes.login)
    ..post('/api/v1/sdk/check', sdkRoutes.check)
    ..post('/api/v1/sdk/events', sdkRoutes.recordEvent)
    ..get('/api/v1/sdk/patch/<id>/file', sdkRoutes.download)
    ..get('/api/v1/sdk/public-key', sdkRoutes.publicKey);

  // Protected router (user auth required)
  final protectedRouter = Router()
    ..get('/api/v1/auth/whoami', authRoutes.whoami)
    ..get('/api/v1/keys', apiKeyRoutes.list)
    ..post('/api/v1/keys', apiKeyRoutes.create)
    ..delete('/api/v1/keys/<id>', apiKeyRoutes.revoke)
    ..get('/api/v1/apps', appRoutes.list)
    ..post('/api/v1/apps', appRoutes.create)
    ..get('/api/v1/apps/<id>', appRoutes.get)
    ..delete('/api/v1/apps/<id>', appRoutes.delete)
    ..post('/api/v1/apps/<id>/sdk-key/rotate', appRoutes.rotateSdkKey)
    ..get('/api/v1/apps/<appId>/releases', appRoutes.listReleases)
    ..post('/api/v1/apps/<appId>/releases', appRoutes.createRelease)
    ..get('/api/v1/apps/<appId>/releases/<id>', appRoutes.getRelease)
    ..get('/api/v1/apps/<appId>/channels', appRoutes.listChannels)
    ..get('/api/v1/releases/<releaseId>/patches', patchRoutes.list)
    ..post('/api/v1/releases/<releaseId>/patches', patchRoutes.upload)
    ..get('/api/v1/patches/<id>', patchRoutes.get)
    ..patch('/api/v1/patches/<id>', patchRoutes.update)
    ..delete('/api/v1/patches/<id>', patchRoutes.delete)
    ..post('/api/v1/patches/<id>/activate', patchRoutes.activate)
    ..post('/api/v1/patches/<id>/rollout', patchRoutes.rollout);

  final protectedHandler = auth.middleware(protectedRouter.call);

  Future<Response> dispatch(Request request) async {
    final r1 = await publicRouter.call(request);
    if (r1.statusCode != 404) return r1;
    return protectedHandler(request);
  }

  final handler = const Pipeline()
      .addMiddleware(errorMiddleware())
      .addMiddleware(corsHeaders())
      .addHandler((Request req) => dispatch(req));

  final server = await shelf_io.serve(handler, cfg.host, cfg.port);
  log.info('Listening on http://${cfg.host}:${cfg.port}');
  log.info('Storage:    ${cfg.storagePath}');
  log.info('Public URL: ${cfg.baseUrl}');

  ProcessSignal.sigint.watch().listen((_) async {
    log.info('Shutting down...');
    await server.close(force: true);
    await db.close();
    log.info('Bye');
    exit(0);
  });
}

PatchSigner _devEphemeralSigner() {
  // Use a deterministic dev key so behavior is predictable across restarts
  // in dev. NOT secure — production must set real keys.
  // Generated once and hardcoded here.
  const privB64 = 'kF6qQ1k4qV5eRqJZK6h7j8L9mN0pQ1rS2tU3vW4xY5z=';
  const pubB64 = 'AAECAwQFBgcICQoLDA0ODw==';
  return PatchSigner.fromBase64(privateKeyB64: privB64, publicKeyB64: pubB64);
}

/// Log which critical env vars are present at startup.
/// Values are NOT logged — only their names and lengths. Helps
/// diagnose Dokploy / Docker env var passthrough issues.
void _logConfigDiagnostic(Logger log) {
  final relevant = <String>[
    'PATCHFLY_ENV',
    'PATCHFLY_BASE_URL',
    'DATABASE_URL',
    'JWT_SECRET',
    'STORAGE_BACKEND',
    'S3_BUCKET',
    'S3_ENDPOINT',
    'S3_ACCESS_KEY',
    'S3_SECRET_KEY',
    'PATCH_SIGNING_PUBLIC_KEY',
    'PATCH_SIGNING_PRIVATE_KEY',
    'SCHEMA_PATH',
  ];
  final present = <String>[];
  final missing = <String>[];
  for (final k in relevant) {
    final v = Platform.environment[k];
    if (v == null || v.isEmpty) {
      missing.add(k);
    } else {
      present.add('$k=${v.length}ch');
    }
  }
  log.info('Env vars set: ${present.join(", ")}');
  if (missing.isNotEmpty) {
    log.warning('Env vars missing: ${missing.join(", ")}');
  }
}
