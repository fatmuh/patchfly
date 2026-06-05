// Patch model.

import 'models.dart' show Row;

class Patch {
  final String id;
  final String releaseId;
  final int patchNumber;
  final String filePath;
  final int fileSizeBytes;
  final String sha256Hash;
  final String signature;
  final String? minAppVersion;
  final String? maxAppVersion;
  final int rolloutPercent;
  final bool isActive;
  final String? basePatchId;
  final bool isDelta;
  final int downloadCount;
  final DateTime createdAt;

  Patch({
    required this.id,
    required this.releaseId,
    required this.patchNumber,
    required this.filePath,
    required this.fileSizeBytes,
    required this.sha256Hash,
    required this.signature,
    this.minAppVersion,
    this.maxAppVersion,
    required this.rolloutPercent,
    required this.isActive,
    this.basePatchId,
    required this.isDelta,
    required this.downloadCount,
    required this.createdAt,
  });

  factory Patch.fromRow(Row r) => Patch(
        id: r.col<String>('id'),
        releaseId: r.col<String>('release_id'),
        patchNumber: r.col<int>('patch_number'),
        filePath: r.col<String>('file_path'),
        fileSizeBytes: r.col<int>('file_size_bytes'),
        sha256Hash: r.col<String>('sha256_hash'),
        signature: r.col<String>('signature'),
        minAppVersion: r.nullable<String>('min_app_version'),
        maxAppVersion: r.nullable<String>('max_app_version'),
        rolloutPercent: r.nullable<int>('rollout_percent') ?? 100,
        isActive: r.nullable<bool>('is_active') ?? false,
        basePatchId: r.nullable<String>('base_patch_id'),
        isDelta: r.nullable<bool>('is_delta') ?? false,
        downloadCount: r.nullable<int>('download_count') ?? 0,
        createdAt: r.dateTime('created_at'),
      );

  /// Manifest returned to SDK. Includes signature + URL for download.
  Map<String, dynamic> toManifestJson({required String downloadUrl}) => {
        'id': id,
        'patchNumber': patchNumber,
        'sha256': sha256Hash,
        'signature': signature,
        'sizeBytes': fileSizeBytes,
        'downloadUrl': downloadUrl,
        'isDelta': isDelta,
        'basePatchId': basePatchId,
        'minAppVersion': minAppVersion,
        'maxAppVersion': maxAppVersion,
        'rolloutPercent': rolloutPercent,
        'createdAt': createdAt.toIso8601String(),
      };
}
