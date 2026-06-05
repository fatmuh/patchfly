// Patch service — the heart of Patchfly.

import 'dart:io';
import 'package:logging/logging.dart';
import '../config.dart';
import '../db/database.dart';
import '../models/patch.dart';
import '../models/release.dart';
import '../models/models.dart' show firstRow, allRows;
import '../utils/json.dart';
import '../utils/patch_signer.dart';
import 'storage_service.dart';

class PatchService {
  final Database _db;
  final StorageService _storage;
  final PatchSigner _signer;
  final Logger _log = Logger('PatchService');
  // ignore: unused_field
  final AppConfig _cfg;

  PatchService(this._db, this._storage, this._signer, this._cfg);

  /// Upload a new patch. Returns the patch record.
  Future<Patch> upload({
    required String releaseId,
    required File file,
    required String sha256,
    int? rolloutPercent,
    String? minAppVersion,
    String? maxAppVersion,
    bool activateImmediately = true,
  }) async {
    final nextNum = await _db.queryValue(
      '''SELECT COALESCE(MAX(patch_number), 0) + 1
         FROM patches WHERE release_id = @r''',
      {'r': releaseId},
    ) as int;

    final stored = await _storage.putFile(
      file: file,
      sha256: sha256,
      releaseId: releaseId,
      patchNumber: nextNum,
    );

    final signature = _signer.sign(sha256);

    if (activateImmediately) {
      await _db.execute(
        'UPDATE patches SET is_active = false WHERE release_id = @r',
        {'r': releaseId},
      );
    }

    final rows = await _db.query(
      '''INSERT INTO patches
           (release_id, patch_number, file_path, file_size_bytes,
            sha256_hash, signature, min_app_version, max_app_version,
            rollout_percent, is_active)
         VALUES (@r, @n, @p, @s, @h, @sig, @min, @max, @rollout, @active)
         RETURNING *''',
      {
        'r': releaseId,
        'n': nextNum,
        'p': stored.key,
        's': stored.sizeBytes,
        'h': sha256,
        'sig': signature,
        'min': minAppVersion,
        'max': maxAppVersion,
        'rollout': rolloutPercent ?? 100,
        'active': activateImmediately,
      },
    );

    _log.info(
      'Uploaded patch #$nextNum for release=$releaseId '
      'size=${stored.sizeBytes}B sha=$sha256',
    );

    return firstRow(rows, Patch.fromRow)!;
  }

  Future<List<Patch>> listForRelease(String releaseId) async {
    final rows = await _db.query(
      'SELECT * FROM patches WHERE release_id = @r ORDER BY patch_number DESC',
      {'r': releaseId},
    );
    return allRows(rows, Patch.fromRow);
  }

  Future<Patch?> findById(String id) async {
    final rows = await _db.query(
      'SELECT * FROM patches WHERE id = @i',
      {'i': id},
    );
    return firstRow(rows, Patch.fromRow);
  }

  Future<Patch?> findActiveForRelease(String releaseId) async {
    final rows = await _db.query(
      '''SELECT * FROM patches
         WHERE release_id = @r AND is_active = true
         ORDER BY patch_number DESC LIMIT 1''',
      {'r': releaseId},
    );
    return firstRow(rows, Patch.fromRow);
  }

  Future<Patch> setActive(String patchId, bool active) async {
    final p = await findById(patchId);
    if (p == null) throw NotFound('Patch not found');

    if (active) {
      await _db.execute(
        'UPDATE patches SET is_active = false WHERE release_id = @r',
        {'r': p.releaseId},
      );
    }
    await _db.execute(
      'UPDATE patches SET is_active = @a WHERE id = @i',
      {'a': active, 'i': patchId},
    );
    return (await findById(patchId))!;
  }

  Future<Patch> setRollout(String patchId, int percent) async {
    if (percent < 0 || percent > 100) {
      throw BadRequest('rollout_percent must be 0-100');
    }
    final affected = await _db.execute(
      'UPDATE patches SET rollout_percent = @p WHERE id = @i',
      {'p': percent, 'i': patchId},
    );
    if (affected == 0) throw NotFound('Patch not found');
    return (await findById(patchId))!;
  }

  Future<void> delete(String patchId) async {
    final p = await findById(patchId);
    if (p == null) throw NotFound('Patch not found');
    await _storage.deleteFile(p.filePath);
    await _db.execute('DELETE FROM patches WHERE id = @i', {'i': patchId});
    _log.info('Deleted patch $patchId');
  }

  Future<void> recordDownload(String patchId) async {
    await _db.execute(
      'UPDATE patches SET download_count = download_count + 1 WHERE id = @i',
      {'i': patchId},
    );
  }

  /// Find the latest active patch for an app + channel.
  Future<({Patch patch, Release release, Channel channel})?> findLatestForSdk({
    required String appId,
    required String channelName,
    required String? userAppVersion,
    required String? deviceId,
  }) async {
    final rows = await _db.query(
      '''SELECT
           p.id, p.release_id, p.patch_number, p.file_path, p.file_size_bytes,
           p.sha256_hash, p.signature, p.min_app_version, p.max_app_version,
           p.rollout_percent, p.is_active, p.base_patch_id, p.is_delta,
           p.download_count, p.created_at,
           r.id AS r_id, r.app_id AS r_app_id, r.channel_id AS r_channel_id,
           r.version AS r_version, r.is_active AS r_is_active,
           r.notes AS r_notes, r.created_at AS r_created_at,
           c.id AS c_id, c.name AS c_name, c.app_id AS c_app_id,
           c.created_at AS c_created_at
         FROM patches p
         JOIN releases r ON r.id = p.release_id
         JOIN channels c ON c.id = r.channel_id
         WHERE r.app_id = @a
           AND c.name = @chan
           AND r.is_active = true
           AND p.is_active = true
         ORDER BY p.patch_number DESC
         LIMIT 1''',
      {'a': appId, 'chan': channelName},
    );
    if (rows.isEmpty) return null;

    final r = rows.first;

    final patch = Patch.fromRow(r);
    if (patch.minAppVersion != null &&
        userAppVersion != null &&
        _compareVersions(userAppVersion, patch.minAppVersion!) < 0) {
      return null;
    }
    if (patch.maxAppVersion != null &&
        userAppVersion != null &&
        _compareVersions(userAppVersion, patch.maxAppVersion!) > 0) {
      return null;
    }

    if (patch.rolloutPercent < 100 && deviceId != null) {
      final bucket = _stableBucket(deviceId);
      if (bucket >= patch.rolloutPercent) return null;
    }

    final release = Release(
      id: r.col<String>('r_id'),
      appId: r.col<String>('r_app_id'),
      channelId: r.col<String>('r_channel_id'),
      channelName: r.col<String>('c_name'),
      version: r.col<String>('r_version'),
      isActive: r.col<bool>('r_is_active'),
      notes: r.nullable<String>('r_notes'),
      createdAt: r.dateTime('r_created_at'),
    );
    final channel = Channel(
      id: r.col<String>('c_id'),
      appId: r.col<String>('c_app_id'),
      name: r.col<String>('c_name'),
      createdAt: r.dateTime('c_created_at'),
    );

    return (patch: patch, release: release, channel: channel);
  }

  /// Stable 0-99 bucket from a string, for rollout targeting.
  static int _stableBucket(String s) {
    var hash = 2166136261;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash % 100;
  }

  /// Compare two dotted versions: 1.2.3 < 1.10.0
  static int _compareVersions(String a, String b) {
    final pa = a.split(RegExp(r'[.+-]'));
    final pb = b.split(RegExp(r'[.+-]'));
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final va = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final vb = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (va < vb) return -1;
      if (va > vb) return 1;
    }
    return 0;
  }
}
