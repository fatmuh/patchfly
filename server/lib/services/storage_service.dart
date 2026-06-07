// Storage abstraction.
//
// Patchfly supports two storage backends:
//   - Local filesystem (default, good for single-server dev/test)
//   - S3 / S3-compatible (MinIO, Cloudflare R2, Backblaze B2, Wasabi,
//     DigitalOcean Spaces, etc.) — recommended for production so you
//     can scale horizontally or use a CDN.
//
// All backends use the same content-addressable layout:
//   <bucket-or-root>/<release_id>/<patch_N>__<sha8>.so

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:minio/minio.dart';
import 'package:logging/logging.dart';
import '../../config.dart';

class StoredFile {
  final String key; // backend-native key (relative path or S3 object key)
  final int sizeBytes;
  const StoredFile(this.key, this.sizeBytes);
}

/// Abstract storage. Implementations: [LocalStorageService], [S3StorageService].
abstract class StorageService {
  Future<void> init();
  Future<StoredFile> putFile({
    required File file,
    required String sha256,
    required String releaseId,
    required int patchNumber,
  });
  Stream<List<int>> openRead(String key);
  Future<void> deleteFile(String key);
  Future<void> close();

  /// Public URL for direct download. May be a presigned URL, a CDN URL,
  /// or a proxy URL through our server. The SDK can use either.
  String publicUrlFor(String key, {required String baseUrl});

  /// Factory: pick backend from config.
  static Future<StorageService> fromConfig(AppConfig cfg) async {
    switch (cfg.storageBackend.toLowerCase()) {
      case 's3':
      case 's3-compatible':
      case 'minio':
      case 'r2':
        final s = S3StorageService(cfg);
        await s.init();
        return s;
      case 'local':
      case 'fs':
      case 'filesystem':
      default:
        final s = LocalStorageService(cfg.storagePath);
        await s.init();
        return s;
    }
  }
}

// ============================================================
// Local filesystem implementation
// ============================================================

class LocalStorageService implements StorageService {
  final String root;
  final Logger _log = Logger('LocalStorage');

  LocalStorageService(this.root);

  @override
  Future<void> init() async {
    final dir = Directory(root);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _log.info('Local storage at $root');
  }

  @override
  Future<StoredFile> putFile({
    required File file,
    required String sha256,
    required String releaseId,
    required int patchNumber,
  }) async {
    final shaPrefix = sha256.substring(0, 8);
    final ext = p.extension(file.path).isNotEmpty ? p.extension(file.path) : '';
    final fileName = '${patchNumber}_$shaPrefix$ext';
    final key = p.join(releaseId, fileName);
    final dest = File(p.join(root, key));

    await dest.parent.create(recursive: true);
    await file.copy(dest.path);

    return StoredFile(key, await dest.length());
  }

  @override
  Stream<List<int>> openRead(String key) {
    return File(p.join(root, key)).openRead();
  }

  @override
  Future<void> deleteFile(String key) async {
    final f = File(p.join(root, key));
    if (await f.exists()) await f.delete();
  }

  @override
  String publicUrlFor(String key, {required String baseUrl}) {
    return '$baseUrl/storage/$key';
  }

  @override
  Future<void> close() async {}
}

// ============================================================
// S3 / S3-compatible implementation
//
// Works with:
//   - AWS S3
//   - MinIO
//   - Cloudflare R2
//   - Backblaze B2 (S3-compatible mode)
//   - Wasabi
//   - DigitalOcean Spaces
//   - Any other service implementing the S3 API
// ============================================================

class S3StorageService implements StorageService {
  final AppConfig _cfg;
  final Logger _log = Logger('S3Storage');
  late final Minio _client;
  late final String _bucket;

  S3StorageService(this._cfg);

  @override
  Future<void> init() async {
    final bucket = _cfg.s3Bucket;
    if (bucket == null || bucket.isEmpty) {
      throw StateError(
          'S3_BUCKET is required when STORAGE_BACKEND=s3. '
          'Set it in your environment / Dokploy config.');
    }
    _bucket = bucket;

    final endpoint = _cfg.s3Endpoint ?? 's3.amazonaws.com';
    final useSSL = _cfg.s3UseSsl;

    _client = Minio(
      endPoint: _stripScheme(endpoint),
      port: _portFromEndpoint(endpoint),
      accessKey: _cfg.s3AccessKey ?? '',
      secretKey: _cfg.s3SecretKey ?? '',
      useSSL: useSSL,
      region: _cfg.s3Region,
      // pathStyle: true is required for most S3-compatible services
      // (MinIO, R2, B2, DO Spaces, Wasabi). AWS S3 itself supports
      // both, so we default to path-style for portability.
      pathStyle: true,
    );

    // Verify bucket exists; create if not.
    final exists = await _client.bucketExists(bucket);
    if (!exists) {
      if (_cfg.s3AutoCreateBucket) {
        _log.info('Bucket $bucket does not exist, creating...');
        await _client.makeBucket(bucket, _cfg.s3Region ?? 'us-east-1');
      } else {
        throw StateError(
          'S3 bucket "$bucket" does not exist and S3_AUTO_CREATE_BUCKET=false. '
          'Either create it manually or set S3_AUTO_CREATE_BUCKET=true.');
      }
    }
    _log.info('S3 storage ready (bucket=$bucket, endpoint=$endpoint)');
  }

  @override
  Future<StoredFile> putFile({
    required File file,
    required String sha256,
    required String releaseId,
    required int patchNumber,
  }) async {
    final shaPrefix = sha256.substring(0, 8);
    final ext = p.extension(file.path).isNotEmpty ? p.extension(file.path) : '';
    final fileName = '${patchNumber}_$shaPrefix$ext';
    final key = p.join(releaseId, fileName);

    final size = await file.length();
    final stream = file.openRead().map(
        (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk));

    final etag = await _client.putObject(
      _bucket,
      key,
      stream,
      size: size,
    );
    _log.info('Uploaded $key to s3 (size=$size, etag=$etag)');
    return StoredFile(key, size);
  }

  @override
  Stream<List<int>> openRead(String key) async* {
    final result = await _client.getObject(_bucket, key);
    yield* result;
  }

  @override
  Future<void> deleteFile(String key) async {
    await _client.removeObject(_bucket, key);
  }

  @override
  String publicUrlFor(String key, {required String baseUrl}) {
    // By default we proxy through our server. If S3_PUBLIC_URL is set,
    // generate a direct URL the SDK can hit.
    final publicBase = _cfg.s3PublicUrl;
    if (publicBase == null || publicBase.isEmpty) {
      return '$baseUrl/storage/$key';
    }
    return '$publicBase/${_bucket}/$key';
  }

  @override
  Future<void> close() async {
    // minio client has no close() — nothing to do
  }

  static String _stripScheme(String endpoint) {
    if (endpoint.startsWith('https://')) return endpoint.substring(8);
    if (endpoint.startsWith('http://')) return endpoint.substring(7);
    return endpoint;
  }

  static int? _portFromEndpoint(String endpoint) {
    final stripped = _stripScheme(endpoint);
    final slash = stripped.indexOf('/');
    final hostPart = slash < 0 ? stripped : stripped.substring(0, slash);
    final colon = hostPart.indexOf(':');
    if (colon < 0) return null;
    return int.tryParse(hostPart.substring(colon + 1));
  }
}
