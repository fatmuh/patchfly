// SDK-facing routes.

import 'package:shelf/shelf.dart';
import '../models/app.dart';
import '../services/app_service.dart';
import '../services/asset_service.dart';
import '../services/event_service.dart';
import '../services/patch_service.dart';
import '../services/release_service.dart';
import '../services/storage_service.dart';
import '../utils/json.dart';
import '../utils/json_response.dart';
import '../utils/patch_signer.dart';

class SdkRoutes {
  final AppService apps;
  final PatchService patches;
  final ReleaseService releases;
  final StorageService storage;
  final EventService events;
  final PatchSigner signer;
  final AssetService assets;

  SdkRoutes(
    this.apps,
    this.patches,
    this.releases,
    this.storage,
    this.events,
    this.signer,
    this.assets,
  );

  Future<App?> _auth(Request request) async {
    final key = request.headers['x-patchfly-sdk-key'];
    if (key == null || key.isEmpty) return null;
    return apps.authenticateSdkKey(key);
  }

  Future<Response> check(Request request) async {
    final app = await _auth(request);
    if (app == null) {
      return jsonResponse(
          {'error': 'unauthorized', 'message': 'Invalid SDK key'},
          status: 401);
    }
    final body = await _readJson(request);
    final channel = Validation.optionalString(body, 'channel') ?? 'stable';
    final appVersion = Validation.optionalString(body, 'appVersion');
    final deviceId = Validation.optionalString(body, 'deviceId');
    final platform = Validation.optionalString(body, 'platform') ?? 'android';
    final activePatchNumber = body['activePatchNumber'] as int?;

    if (app.platform != platform && app.platform != 'all') {
      return jsonResponse({'update': null});
    }

    final result = await patches.findLatestForSdk(
      appId: app.id,
      channelName: channel,
      userAppVersion: appVersion,
      deviceId: deviceId,
    );

    // If the device already has the latest patch, don't send it again.
    // This prevents the download-apply-restart loop.
    if (result != null && activePatchNumber != null) {
      if (result.patch.patchNumber <= activePatchNumber) {
        return jsonResponse({'update': null});
      }
    }

    await events.record(
      patchId: result?.patch.id,
      appId: app.id,
      eventType: 'check',
      appVersion: appVersion,
      deviceId: deviceId,
      metadata: {'channel': channel, 'hasUpdate': result != null},
    );

    if (result == null) {
      return jsonResponse({'update': null});
    }

    final downloadUrl = '/api/v1/sdk/patch/${result.patch.id}/file';
    return jsonResponse({
      'update': {
        'patch': result.patch.toManifestJson(downloadUrl: downloadUrl),
        'release': {
          'id': result.release.id,
          'version': result.release.version,
          'notes': result.release.notes,
          'channel': result.channel.name,
        },
      },
    });
  }

  Future<Response> recordEvent(Request request) async {
    final app = await _auth(request);
    if (app == null) {
      return jsonResponse(
          {'error': 'unauthorized', 'message': 'Invalid SDK key'},
          status: 401);
    }
    final body = await _readJson(request);
    final eventType = Validation.requireString(body, 'eventType');
    if (!{'check', 'download', 'apply', 'error'}.contains(eventType)) {
      throw BadRequest(
          'eventType must be one of: check, download, apply, error');
    }
    await events.record(
      patchId: Validation.optionalString(body, 'patchId'),
      appId: app.id,
      eventType: eventType,
      appVersion: Validation.optionalString(body, 'appVersion'),
      deviceId: Validation.optionalString(body, 'deviceId'),
      errorMessage: Validation.optionalString(body, 'errorMessage'),
      metadata: Validation.optionalString(body, 'metadata') != null
          ? {'raw': Validation.optionalString(body, 'metadata')}
          : null,
    );
    return jsonResponse({'ok': true});
  }

  Future<Response> download(Request request, String id) async {
    final app = await _auth(request);
    if (app == null) {
      return jsonResponse(
          {'error': 'unauthorized', 'message': 'Invalid SDK key'},
          status: 401);
    }
    final p = await patches.findById(id);
    if (p == null) throw NotFound('Patch not found');
    final rel = await releases.findById(p.releaseId);
    if (rel == null || rel.appId != app.id) {
      throw NotFound('Patch not found');
    }

    await patches.recordDownload(id);
    await events.record(patchId: id, appId: app.id, eventType: 'download');

    final stream = storage.openRead(p.filePath);
    return Response.ok(
      stream,
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': p.fileSizeBytes.toString(),
        'content-disposition':
            'attachment; filename="patch_${p.patchNumber}${p.filePath.contains('.') ? '.${p.filePath.split('.').last}' : ''}"',
        'x-patchfly-sha256': p.sha256Hash,
        'x-patchfly-signature': p.signature,
        'x-patchfly-patch-number': p.patchNumber.toString(),
      },
    );
  }

  Future<Response> publicKey(Request request) async {
    return jsonResponse({
      'publicKey': signer.publicKeyBase64,
      'algorithm': 'ed25519',
    });
  }
}

Future<Map<String, dynamic>> _readJson(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) throw BadRequest('Request body is required');
  try {
    return JsonUtils.decodeMap(body);
  } on FormatException catch (e) {
    throw BadRequest('Invalid JSON: ${e.message}');
  }
}

// ====================================================================
// ASSET / CONFIG OTA ENDPOINTS
// ====================================================================

extension SdkAssetRoutes on SdkRoutes {
  /// GET /api/v1/sdk/asset-check?currentVersion=N
  /// Returns { available: true, version, sha256, sizeBytes, changelog }
  /// or { available: false }
  Future<Response> assetCheck(Request request) async {
    final app = await _auth(request);
    if (app == null) {
      return jsonResponse(
          {'error': 'unauthorized', 'message': 'Invalid SDK key'},
          status: 401);
    }
    final currentVersion =
        int.tryParse(request.url.queryParameters['currentVersion'] ?? '0') ?? 0;
    final latest = await assets.findLatest(app.id, currentVersion: currentVersion);
    if (latest == null) {
      return jsonResponse({'available': false});
    }
    return jsonResponse({
      'available': true,
      'version': latest.version,
      'sha256': latest.sha256,
      'sizeBytes': latest.sizeBytes,
      'changelog': latest.changelog,
    });
  }

  /// GET /api/v1/sdk/asset/<version>
  /// Returns the raw zip bytes.
  Future<Response> assetDownload(Request request) async {
    final app = await _auth(request);
    if (app == null) {
      return jsonResponse(
          {'error': 'unauthorized', 'message': 'Invalid SDK key'},
          status: 401);
    }
    final versionStr = _getPathParam(request, 'version');
    final version = int.tryParse(versionStr ?? '');
    if (version == null) {
      return jsonResponse({'error': 'bad_request'}, status: 400);
    }
    // Find by version (any newer or matching)
    final asset = await assets.findLatest(app.id, currentVersion: version - 1);
    if (asset == null || asset.version != version) {
      return jsonResponse({'error': 'not_found'}, status: 404);
    }
    final bytes = await assets.download(asset);
    return Response.ok(
      bytes,
      headers: {
        'content-type': 'application/zip',
        'content-length': '${bytes.length}',
        'x-patchfly-asset-version': '${asset.version}',
        'x-patchfly-asset-sha256': asset.sha256,
      },
    );
  }
}

String? _getPathParam(Request request, String name) {
  // shelf_router strips path params and they're accessible via the matched
  // route, but Request doesn't expose them directly. Parse the URL.
  final segments = request.url.pathSegments;
  // /api/v1/sdk/asset/<version>
  if (segments.length >= 5 && segments[3] == 'asset' && name == 'version') {
    return segments[4];
  }
  return null;
}
