// lib/services/asset_service.dart
//
// Manages per-app asset/config bundles.
// An "asset" is a zip of arbitrary files (json, txt, png, ttf, html, ...).
// Each upload increments a per-app version counter. The SDK polls
// /api/v1/sdk/asset-check?currentVersion=N to discover newer versions.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import 'storage_service.dart';

class Asset {
  final String id;
  final String appId;
  final int version;
  final String storageKey;
  final int sizeBytes;
  final String sha256;
  final String? changelog;
  final DateTime createdAt;

  const Asset({
    required this.id,
    required this.appId,
    required this.version,
    required this.storageKey,
    required this.sizeBytes,
    required this.sha256,
    this.changelog,
    required this.createdAt,
  });

  factory Asset.fromRow(Row r) {
    String? changelog;
    try {
      final v = r.col<dynamic>('changelog');
      changelog = v?.toString();
    } catch (_) {
      changelog = null;
    }
    return Asset(
      id: r.col<String>('id'),
      appId: r.col<String>('app_id'),
      version: r.col<int>('version'),
      storageKey: r.col<String>('storage_key'),
      sizeBytes: r.col<int>('size_bytes'),
      sha256: r.col<String>('sha256'),
      changelog: changelog,
      createdAt: r.dateTime('created_at'),
    );
  }
}

class AssetService {
  final Database db;
  final StorageService storage;

  AssetService(this.db, this.storage);

  Future<Asset?> findLatest(String appId, {int currentVersion = 0}) async {
    final r = await db.query(
      '''
      SELECT * FROM assets
      WHERE app_id = @appId AND version > @currentVersion
      ORDER BY version DESC
      LIMIT 1
      ''',
      {'appId': appId, 'currentVersion': currentVersion},
    );
    if (r.isEmpty) return null;
    return Asset.fromRow(r.first);
  }

  Future<Uint8List> download(Asset asset) async {
    final stream = storage.openRead(asset.storageKey);
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  Future<Asset> upload({
    required String appId,
    required Uint8List bytes,
    required String sha256,
    String? changelog,
    String? createdByUserId,
  }) async {
    final r = await db.query(
      'SELECT COALESCE(MAX(version), 0) + 1 AS next FROM assets WHERE app_id = @appId',
      {'appId': appId},
    );
    final nextVersion = r.first.col<int>('next');
    final id = const Uuid().v4();
    final storageKey = 'assets/$appId/v$nextVersion.zip';

    // Write to temp file (existing putFile API takes a File)
    final tmp = File(p.join(
        Directory.systemTemp.path, 'patchfly-asset-$id.zip'));
    await tmp.writeAsBytes(bytes);
    try {
      // Reuse the patch storage layout
      await storage.putFile(
        file: tmp,
        sha256: sha256,
        releaseId: appId,
        patchNumber: nextVersion + 100000,
      );
    } finally {
      await tmp.delete();
    }

    await db.execute(
      '''
      INSERT INTO assets (id, app_id, version, storage_key, size_bytes, sha256, changelog, created_by)
      VALUES (@id, @appId, @version, @storageKey, @sizeBytes, @sha256, @changelog, @createdBy)
      ''',
      {
        'id': id,
        'appId': appId,
        'version': nextVersion,
        'storageKey': storageKey,
        'sizeBytes': bytes.length,
        'sha256': sha256,
        'changelog': changelog,
        'createdBy': createdByUserId,
      },
    );

    return Asset(
      id: id,
      appId: appId,
      version: nextVersion,
      storageKey: storageKey,
      sizeBytes: bytes.length,
      sha256: sha256,
      changelog: changelog,
      createdAt: DateTime.now(),
    );
  }
}
