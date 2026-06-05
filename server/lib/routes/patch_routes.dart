// Patch routes — list, upload, control.

import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/form_data.dart';
import '../config.dart';
import '../services/app_service.dart';
import '../services/patch_service.dart';
import '../services/release_service.dart';
import '../utils/hash.dart';
import '../utils/json.dart';
import '../utils/json_response.dart';

class PatchRoutes {
  final AppService apps;
  final ReleaseService releases;
  final PatchService patches;
  final AppConfig cfg;

  PatchRoutes(this.apps, this.releases, this.patches, this.cfg);

  Future<Response> list(Request request, String releaseId) async {
    await _verifyReleaseOwnership(releaseId, _userId(request));
    final list = await patches.listForRelease(releaseId);
    return jsonResponse({
      'patches':
          list.map((p) => p.toManifestJson(downloadUrl: _downloadUrl(p.id))).toList(),
    });
  }

  Future<Response> upload(Request request, String releaseId) async {
    await _verifyReleaseOwnership(releaseId, _userId(request));
    final rel = await releases.findById(releaseId);
    if (rel == null) throw NotFound('Release not found');

    if (!request.isMultipartForm) {
      throw BadRequest('Expected multipart/form-data');
    }

    final maxBytes = cfg.maxPatchSizeMb * 1024 * 1024;
    File? uploadedFile;
    String? uploadedSha;
    final formParts = <String, String>{};

    await for (final formData in request.multipartFormData) {
      if (formData.filename != null) {
        // File part
        final bytes = <int>[];
        await for (final chunk in formData.part) {
          if (bytes.length + chunk.length > maxBytes) {
            throw BadRequest(
              'Patch exceeds max size of ${cfg.maxPatchSizeMb} MB',
            );
          }
          bytes.addAll(chunk);
        }
        final tmp = await _writeTemp(bytes);
        uploadedFile = tmp;
        uploadedSha = sha256BytesHex(bytes);
        formParts['sha256'] = uploadedSha;
        formParts['size'] = bytes.length.toString();
      } else {
        // Form field
        final bytes = <int>[];
        await for (final chunk in formData.part) {
          bytes.addAll(chunk);
        }
        formParts[formData.name] = utf8.decode(bytes);
      }
    }

    if (uploadedFile == null || uploadedSha == null) {
      throw BadRequest('multipart upload must include a file part');
    }

    if (formParts.containsKey('clientSha256') &&
        formParts['clientSha256'] != uploadedSha) {
      await uploadedFile.delete();
      throw BadRequest('sha256 mismatch (client vs server)');
    }

    final patch = await patches.upload(
      releaseId: releaseId,
      file: uploadedFile,
      sha256: uploadedSha,
      rolloutPercent: Validation.optionalInt(formParts, 'rolloutPercent'),
      minAppVersion: Validation.optionalString(formParts, 'minAppVersion'),
      maxAppVersion: Validation.optionalString(formParts, 'maxAppVersion'),
      activateImmediately:
          (Validation.optionalString(formParts, 'activate') ?? 'true')
                  .toLowerCase() !=
              'false',
    );

    await uploadedFile.delete().catchError((_) => uploadedFile!);

    return jsonResponse(
      {'patch': patch.toManifestJson(downloadUrl: _downloadUrl(patch.id))},
      status: 201,
    );
  }

  Future<Response> get(Request request, String id) async {
    final p = await patches.findById(id);
    if (p == null) throw NotFound('Patch not found');
    await _verifyReleaseOwnership(p.releaseId, _userId(request));
    return jsonResponse({
      'patch': p.toManifestJson(downloadUrl: _downloadUrl(p.id)),
    });
  }

  Future<Response> update(Request request, String id) async {
    final p = await patches.findById(id);
    if (p == null) throw NotFound('Patch not found');
    await _verifyReleaseOwnership(p.releaseId, _userId(request));

    final body = await _readJson(request);
    if (body.containsKey('isActive')) {
      final v = Validation.requireString(body, 'isActive');
      await patches.setActive(id, v.toLowerCase() == 'true');
    }
    final updated = (await patches.findById(id))!;
    return jsonResponse(
        {'patch': updated.toManifestJson(downloadUrl: _downloadUrl(updated.id))});
  }

  Future<Response> delete(Request request, String id) async {
    final p = await patches.findById(id);
    if (p == null) throw NotFound('Patch not found');
    await _verifyReleaseOwnership(p.releaseId, _userId(request));
    await patches.delete(id);
    return jsonResponse({'deleted': true});
  }

  Future<Response> activate(Request request, String id) async {
    final p = await patches.findById(id);
    if (p == null) throw NotFound('Patch not found');
    await _verifyReleaseOwnership(p.releaseId, _userId(request));
    final updated = await patches.setActive(id, true);
    return jsonResponse(
        {'patch': updated.toManifestJson(downloadUrl: _downloadUrl(updated.id))});
  }

  Future<Response> rollout(Request request, String id) async {
    final p = await patches.findById(id);
    if (p == null) throw NotFound('Patch not found');
    await _verifyReleaseOwnership(p.releaseId, _userId(request));
    final body = await _readJson(request);
    final percent = Validation.optionalInt(body, 'percent') ??
        (throw BadRequest('percent (0-100) is required'));
    final updated = await patches.setRollout(id, percent);
    return jsonResponse(
        {'patch': updated.toManifestJson(downloadUrl: _downloadUrl(updated.id))});
  }

  // ---- Helpers ----

  /// Public download URL for a patch, derived from server's public base URL.
  /// Requires PATCHFLY_BASE_URL env var (default: http://localhost:8080).
  /// Set to your public domain (e.g. https://api.patchfly.dev) in production.
  String _downloadUrl(String patchId) =>
      '${cfg.baseUrl}/api/v1/patches/$patchId/file';

  String _userId(Request req) {
    final id = req.context['userId'] as String?;
    if (id == null) throw StateError('userId missing in context');
    return id;
  }

  Future<void> _verifyReleaseOwnership(
      String releaseId, String userId) async {
    final rel = await releases.findById(releaseId);
    if (rel == null) throw NotFound('Release not found');
    final app = await apps.findById(rel.appId, ownerId: userId);
    if (app == null) throw NotFound('Release not found');
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

Future<File> _writeTemp(List<int> bytes) async {
  final dir = Directory.systemTemp.createTempSync('patchfly_upload_');
  final f = File('${dir.path}/patch_${DateTime.now().microsecondsSinceEpoch}');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}
