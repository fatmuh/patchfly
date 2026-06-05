// lib/src/asset_manager.dart
//
// Asset/config OTA layer for Patchfly. Works on any Flutter engine
// (stock, Shorebird's, or any other) — does not require engine fork.
//
// Patches are zip files containing arbitrary key-value files
// (json config, text, images, fonts, html, etc.). The app reads
// via AssetManager.readString/readJson/readBytes with a bundled
// fallback.
//
// Typical flow:
//   1. CLI uploads zip → server stores, signs, increments version
//   2. App on startup → AssetManager.checkForUpdate()
//   3. App downloads → Atomic swap (extract to temp, then rename)
//   4. App re-reads assets → new content visible
//   5. Old content preserved as fallback if new fails to extract

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:patchfly/src/logger.dart';
import 'package:patchfly/src/sha256_util.dart';

class AssetUpdateInfo {
  final int version;
  final String sha256;
  final int sizeBytes;
  final String? changelog;

  const AssetUpdateInfo({
    required this.version,
    required this.sha256,
    required this.sizeBytes,
    this.changelog,
  });

  factory AssetUpdateInfo.fromJson(Map<String, dynamic> j) => AssetUpdateInfo(
        version: j['version'] as int,
        sha256: j['sha256'] as String,
        sizeBytes: j['sizeBytes'] as int? ?? 0,
        changelog: j['changelog'] as String?,
      );
}

class AssetManager {
  AssetManager._();
  static final AssetManager instance = AssetManager._();

  late String _serverUrl;
  late String _sdkKey;
  late Directory _filesDir;
  String? _deviceId;
  bool _initialised = false;

  int? _currentVersion;
  int? get currentVersion => _currentVersion;

  /// Where extracted assets live. Use as base for your key paths.
  /// Example: filesDir/patchfly/assets/config/pricing.json
  String get assetsDirPath => p.join(_filesDir.path, 'patchfly', 'assets');

  Future<void> init({
    required String serverUrl,
    required String sdkKey,
    required Directory filesDir,
    String? deviceId,
  }) async {
    _serverUrl = serverUrl;
    _sdkKey = sdkKey;
    _filesDir = filesDir;
    _deviceId = deviceId;
    final base = Directory(assetsDirPath);
    if (!base.existsSync()) base.createSync(recursive: true);
    await _loadManifest();
    _initialised = true;
    PatchflyLogger.info(
        'AssetManager ready (current version: ${_currentVersion ?? 'none'})');
  }

  void _checkInit() {
    if (!_initialised) {
      throw StateError(
          'AssetManager.init() not called. Call it from Patchfly.init().');
    }
  }

  Future<void> _loadManifest() async {
    final f = File(p.join(assetsDirPath, 'manifest.json'));
    if (!f.existsSync()) return;
    try {
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _currentVersion = data['version'] as int?;
    } catch (_) {
      _currentVersion = null;
    }
  }

  /// Returns the new version if available, null otherwise.
  Future<AssetUpdateInfo?> checkForUpdate() async {
    _checkInit();
    try {
      final uri = Uri.parse(
        '$_serverUrl/api/v1/sdk/asset-check'
        '?currentVersion=${_currentVersion ?? 0}',
      );
      final r = await http.get(uri, headers: _headers());
      if (r.statusCode != 200) {
        PatchflyLogger.warn('Asset check: ${r.statusCode} ${r.reasonPhrase}');
        return null;
      }
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['available'] != true) return null;
      return AssetUpdateInfo.fromJson(data);
    } catch (e, st) {
      PatchflyLogger.warn('Asset check error: $e\n$st');
      return null;
    }
  }

  /// Download + verify + atomic swap. Returns true on success.
  Future<bool> downloadAndApply(AssetUpdateInfo info) async {
    _checkInit();
    try {
      PatchflyLogger.info('Downloading asset v${info.version} (${info.sizeBytes} B)...');
      final r = await http.get(
        Uri.parse('$_serverUrl/api/v1/sdk/asset/${info.version}'),
        headers: _headers(),
      );
      if (r.statusCode != 200) {
        PatchflyLogger.warn('Asset download: ${r.statusCode}');
        return false;
      }
      final bytes = r.bodyBytes;
      // Verify sha256
      final actualHash = _sha256(bytes);
      if (actualHash != info.sha256) {
        PatchflyLogger.warn('Asset hash mismatch: '
            'expected=${info.sha256} got=$actualHash');
        return false;
      }

      // Atomic swap: extract to temp dir then rename files in.
      final tempDir = Directory(p.join(assetsDirPath, '_tmp_${info.version}'));
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      tempDir.createSync(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        final outPath = p.join(tempDir.path, f.name);
        if (f.isFile) {
          final outFile = File(outPath);
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(f.content as List<int>);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }

      // Move every file from temp to assets dir
      _clearAssets();
      for (final entry in tempDir.listSync()) {
        final dst = p.join(assetsDirPath, p.basename(entry.path));
        if (entry is File) {
          File(dst).writeAsBytesSync(entry.readAsBytesSync());
        } else if (entry is Directory) {
          _copyDir(entry, Directory(dst));
        }
      }
      tempDir.deleteSync(recursive: true);

      // Update manifest
      _currentVersion = info.version;
      final manifest = File(p.join(assetsDirPath, 'manifest.json'));
      manifest.writeAsStringSync(jsonEncode({
        'version': info.version,
        'sha256': info.sha256,
        'sizeBytes': info.sizeBytes,
        'appliedAt': DateTime.now().toIso8601String(),
      }));

      PatchflyLogger.info('✓ Assets updated to v${info.version}');
      return true;
    } catch (e, st) {
      PatchflyLogger.warn('Asset apply error: $e\n$st');
      return false;
    }
  }

  /// Convenience: check + download + apply.
  Future<bool> checkDownloadApply() async {
    final info = await checkForUpdate();
    if (info == null) return false;
    return downloadAndApply(info);
  }

  /// Read a string asset, falling back to the bundled value.
  /// Returns empty string if not present anywhere.
  String readString(String key, {String bundled = ''}) {
    _checkInit();
    final f = File(p.join(assetsDirPath, key));
    if (f.existsSync()) {
      try {
        return f.readAsStringSync();
      } catch (_) {}
    }
    return bundled;
  }

  /// Read a JSON asset, falling back to the bundled value.
  Map<String, dynamic> readJson(String key,
      {Map<String, dynamic>? bundled}) {
    final s = readString(key);
    if (s.isEmpty) return bundled ?? const {};
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return bundled ?? const {};
    }
  }

  /// Read raw bytes (for images, fonts, etc).
  /// Throws if not present in either override or via a callable fallback.
  Uint8List readBytes(String key) {
    _checkInit();
    final f = File(p.join(assetsDirPath, key));
    if (f.existsSync()) {
      return f.readAsBytesSync();
    }
    throw StateError(
        'Asset "$key" not found. Use readString/readJson with bundled:, '
        'or include the file in your patch zip.');
  }

  /// Returns true if the asset override is present (different from bundled).
  bool hasOverride(String key) {
    _checkInit();
    return File(p.join(assetsDirPath, key)).existsSync();
  }

  Map<String, String> _headers() => {
        'X-Patchfly-SDK-Key': _sdkKey,
        if (_deviceId != null) 'X-Patchfly-Device-Id': _deviceId!,
      };

  String _sha256(List<int> bytes) => Sha256Util.hash(bytes);

// Standalone SHA-256 helper lives in sha256_util.dart.

  void _clearAssets() {
    final dir = Directory(assetsDirPath);
    for (final entry in dir.listSync()) {
      final name = p.basename(entry.path);
      if (name == 'manifest.json') continue; // keep until we rewrite
      if (entry is File) {
        entry.deleteSync();
      } else if (entry is Directory) {
        entry.deleteSync(recursive: true);
      }
    }
  }

  void _copyDir(Directory src, Directory dst) {
    dst.createSync(recursive: true);
    for (final entry in src.listSync()) {
      final newPath = p.join(dst.path, p.basename(entry.path));
      if (entry is File) {
        File(newPath).writeAsBytesSync(entry.readAsBytesSync());
      } else if (entry is Directory) {
        _copyDir(entry, Directory(newPath));
      }
    }
  }
}
