// App management routes — apps, releases, channels.

import 'package:shelf/shelf.dart';
import '../services/app_service.dart';
import '../services/channel_service.dart';
import '../services/patch_service.dart';
import '../services/release_service.dart';
import '../utils/json.dart';
import '../utils/json_response.dart';

class AppRoutes {
  final AppService apps;
  final ReleaseService releases;
  final ChannelService channels;
  final PatchService patches;

  AppRoutes(this.apps, this.releases, this.channels, this.patches);

  // ---- App CRUD ----

  Future<Response> list(Request request) async {
    final list = await apps.listForOwner(_userId(request));
    return jsonResponse({'apps': list.map((a) => a.toJson()).toList()});
  }

  Future<Response> create(Request request) async {
    final body = await _readJson(request);
    final slug = Validation.requireString(body, 'slug', min: 3, max: 200);
    final name = Validation.requireString(body, 'name', min: 1, max: 120);
    final platform = Validation.optionalString(body, 'platform') ?? 'android';

    final r = await apps.register(
      ownerId: _userId(request),
      slug: slug,
      name: name,
      platform: platform,
    );
    return jsonResponse(
      {
        'app': r.app.toJson(),
        'sdkKey': r.sdkKey,
      },
      status: 201,
    );
  }

  Future<Response> get(Request request, String id) async {
    final app = await apps.findById(id, ownerId: _userId(request));
    if (app == null) throw NotFound('App not found');
    return jsonResponse({'app': app.toJson()});
  }

  Future<Response> delete(Request request, String id) async {
    await apps.delete(id, _userId(request));
    return jsonResponse({'deleted': true});
  }

  Future<Response> rotateSdkKey(Request request, String id) async {
    final newKey = await apps.rotateSdkKey(id, _userId(request));
    return jsonResponse({'sdkKey': newKey});
  }

  // ---- Releases ----

  Future<Response> listReleases(Request request, String appId) async {
    await _verifyOwnership(appId, _userId(request));
    final list = await releases.listForApp(appId);
    return jsonResponse({'releases': list.map((r) => r.toJson()).toList()});
  }

  Future<Response> createRelease(Request request, String appId) async {
    await _verifyOwnership(appId, _userId(request));
    final body = await _readJson(request);
    final version = Validation.requireString(body, 'version', min: 1, max: 60);
    final channel = Validation.optionalString(body, 'channel') ?? 'stable';
    final notes = Validation.optionalString(body, 'notes', max: 5000);

    final rel = await releases.create(
      appId: appId,
      channelName: channel,
      version: version,
      notes: notes,
    );
    return jsonResponse({'release': rel.toJson()}, status: 201);
  }

  Future<Response> getRelease(Request request, String appId, String id) async {
    await _verifyOwnership(appId, _userId(request));
    final rel = await releases.findById(id);
    if (rel == null) throw NotFound('Release not found');
    return jsonResponse({'release': rel.toJson()});
  }

  Future<Response> listChannels(Request request, String appId) async {
    await _verifyOwnership(appId, _userId(request));
    final list = await channels.listForApp(appId);
    return jsonResponse({'channels': list.map((c) => c.toJson()).toList()});
  }

  // ---- Helpers ----

  String _userId(Request req) {
    final id = req.context['userId'] as String?;
    if (id == null) throw StateError('userId missing in context');
    return id;
  }

  Future<void> _verifyOwnership(String appId, String userId) async {
    final app = await apps.findById(appId, ownerId: userId);
    if (app == null) throw NotFound('App not found');
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
