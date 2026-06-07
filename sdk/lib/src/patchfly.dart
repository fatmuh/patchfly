// Patchfly SDK main class.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'asset_manager.dart';
import 'logger.dart';
import 'models.dart';

class Patchfly {
  static Patchfly? _instance;
  static Patchfly get instance => _instance ??= Patchfly._();

  Patchfly._();

  PatchflyConfig? _config;
  String? _deviceId;
  String? _appVersion;
  ed.PublicKey? _publicKey;
  String? _localPatchPath;
  AssetManager get assets => AssetManager.instance;

  PatchflyConfig? get config => _config;
  String? get localPatchPath => _localPatchPath;

  /// Initialize the SDK. Safe to call multiple times.
  static Future<void> init({
    required String serverUrl,
    required String sdkKey,
    String channel = 'stable',
    bool verbose = false,
  }) async {
    PatchflyLogger.setup(level: verbose ? Level.ALL : Level.INFO);
    final p = Patchfly._();
    _instance = p;
    await p._init(
      PatchflyConfig(
        serverUrl: serverUrl.replaceAll(RegExp(r'/$'), ''),
        sdkKey: sdkKey,
        channel: channel,
      ),
    );
  }

  Future<void> _init(PatchflyConfig config) async {
    _config = config;
    PatchflyLogger.info('Initializing Patchfly (server=${config.serverUrl})');

    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('patchfly_device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('patchfly_device_id', deviceId);
    }
    _deviceId = deviceId;

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (e) {
      PatchflyLogger.warn('Could not read package info: $e');
    }

    // Initialise the asset/config OTA layer
    try {
      await AssetManager.instance.init(
        serverUrl: _config!.serverUrl,
        sdkKey: _config!.sdkKey,
        filesDir: await getApplicationSupportDirectory(),
        deviceId: _deviceId,
      );
    } catch (e, st) {
      PatchflyLogger.warn('AssetManager init failed: $e\n$st');
    }

    // Fetch server's ed25519 public key
    try {
      final r = await http
          .get(Uri.parse('${config.serverUrl}/api/v1/sdk/public-key'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final pubKeyB64 = j['publicKey'] as String?;
        if (pubKeyB64 != null) {
          final pubBytes = base64Decode(pubKeyB64);
          if (pubBytes.length == 32) {
            _publicKey = ed.PublicKey(pubBytes);
            PatchflyLogger.info(
                'Loaded server public key: ${pubKeyB64.substring(0, pubKeyB64.length < 8 ? pubKeyB64.length : 8)}...');
          }
        }
      }
    } catch (e) {
      PatchflyLogger.warn('Could not fetch server public key: $e');
    }

    _localPatchPath = prefs.getString('patchfly_local_patch_path');
  }

  /// Ask the server whether a newer patch is available.
  Future<PatchflyUpdate?> checkForUpdate() async {
    if (_config == null) {
      throw PatchflyException(
          'Patchfly not initialized. Call Patchfly.init() first.');
    }
    PatchflyLogger.info('Checking for update (channel=${_config!.channel})');
    print('[PATCHFLY-DEBUG] checkForUpdate: reading activePatchNumber...');

    // Read the currently active patch number from the native updater
    // so the server can skip returning the same patch we already have.
    String? activePatchNumber;
    try {
      activePatchNumber = await getActivePatchNumber();
    } catch (_) {}

    try {
      final r = await http.post(
        Uri.parse('${_config!.serverUrl}/api/v1/sdk/check'),
        headers: {
          'X-Patchfly-SDK-Key': _config!.sdkKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'channel': _config!.channel,
          'appVersion': _appVersion,
          'deviceId': _deviceId,
          'platform': _platformString(),
          if (activePatchNumber != null) 'activePatchNumber': int.tryParse(activePatchNumber),
        }),
      ).timeout(const Duration(seconds: 15));

      if (r.statusCode != 200) {
        PatchflyLogger.warn('checkForUpdate returned ${r.statusCode}');
        return null;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['update'] == null) return null;
      return PatchflyUpdate.fromJson(j);
    } on TimeoutException {
      PatchflyLogger.warn('checkForUpdate timed out');
      return null;
    } catch (e) {
      PatchflyLogger.error('checkForUpdate failed', e);
      rethrow;
    }
  }

  /// Download the patch, verify signature, and save to disk.
  Future<String> download(PatchflyUpdate update) async {
    if (_config == null) {
      throw PatchflyException('Patchfly not initialized');
    }
    PatchflyLogger.info('Downloading patch #${update.patchNumber}...');

    final url = update.downloadUrl.startsWith('http')
        ? update.downloadUrl
        : '${_config!.serverUrl}${update.downloadUrl}';

    final r = await http.get(
      Uri.parse(url),
      headers: {'X-Patchfly-SDK-Key': _config!.sdkKey},
    ).timeout(const Duration(minutes: 10));

    if (r.statusCode != 200) {
      throw PatchflyNetworkException('Download failed: HTTP ${r.statusCode}');
    }
    final bytes = r.bodyBytes;

    // Verify SHA-256
    final actualSha = sha256.convert(bytes).toString();
    if (actualSha != update.sha256) {
      throw PatchflyNetworkException(
          'sha256 mismatch: expected ${update.sha256}, got $actualSha');
    }

    // Verify ed25519 signature
    if (_publicKey != null) {
      final ok = _verifySignature(
        messageHash: update.sha256,
        signatureB64: update.signature,
        publicKey: _publicKey!,
      );
      if (!ok) {
        throw PatchflySignatureException('Signature verification failed');
      }
    } else {
      PatchflyLogger.warn(
          'Skipping signature verification: public key not loaded');
    }

    // Save to disk
    final dir = await getApplicationSupportDirectory();
    final patchesDir = Directory('${dir.path}/patchfly/patches');
    await patchesDir.create(recursive: true);
    final file = File(
      '${patchesDir.path}/patch_${update.patchNumber}_${update.sha256.substring(0, 8)}${_patchFileExtension()}',
    );
    await file.writeAsBytes(bytes, flush: true);

    PatchflyLogger.info('Saved patch to ${file.path}');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('patchfly_local_patch_path', file.path);
    _localPatchPath = file.path;

    unawaited(_recordEvent('download', update: update));

    return file.path;
  }

  /// Apply a downloaded patch.
  ///
  /// The Android side stages the patch into the location the native updater
  /// expects: `<cacheDir>/patches/<patchNumber>/libapp.so` (for full-file
  /// format) or `<cacheDir>/patches/<patchNumber>/patch.bin` (for bsdiff).
  /// On the next launch, `PatchflyApplication.tryInitUpdater()` calls
  /// `shorebirdUpdate()` which finds the patch and applies it.
  /// `PatchflyFlutterLoader` then points the engine at the patched file.
  Future<void> apply(
    String patchFilePath, {
    required int patchNumber,
    String? sha256,
  }) async {
    PatchflyLogger.info('Applying patch #$patchNumber from $patchFilePath');
    try {
      const channel = MethodChannel('patchfly/apply');
      await channel.invokeMethod('apply', {
        'path': patchFilePath,
        'patchNumber': patchNumber,
        'sha256': sha256,
      });
      // Note: we don't persist active_patch_number here because the
      // platform side will kill the process before this returns.
      // The Kotlin plugin writes it to FlutterSharedPreferences instead.
    } on PlatformException catch (e) {
      throw PatchflyApplyException('Platform apply failed: ${e.message}');
    } on MissingPluginException {
      throw PatchflyApplyException(
          'No Patchfly platform integration. See docs/ANDROID_INTEGRATION.md or docs/IOS_INTEGRATION.md');
    }
  }

  /// Returns the active libapp.so path (from native updater).
  /// Returns null if no updater is loaded or no active path.
  Future<String?> getActiveLibappPath() async {
    try {
      const channel = MethodChannel('patchfly/apply');
      return await channel.invokeMethod<String>('getActivePath');
    } on PlatformException catch (e) {
      PatchflyLogger.warn('getActivePath failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Returns the active patch number (from native updater).
  /// Returns null if no updater is loaded or no active patch.
  Future<String?> getActivePatchNumber() async {
    // First try SharedPreferences — the Kotlin plugin writes to
    // FlutterSharedPreferences with key flutter.patchfly_active_patch_number
    // (synchronous commit before process kill).
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt('patchfly_active_patch_number');
      PatchflyLogger.info('SharedPreferences cached = $cached');
      if (cached != null) {
        PatchflyLogger.info('Active patch from SharedPreferences: #$cached');
        return cached.toString();
      }
    } catch (e) {
      PatchflyLogger.warn('SharedPreferences read failed: $e');
    }
    // Then try marker file
    try {
      final dir = await getApplicationSupportDirectory();
      final marker = File('${dir.path}/patchfly/active_patch_number');
      if (await marker.exists()) {
        final content = await marker.readAsString();
        final num = int.tryParse(content.trim());
        if (num != null) {
          PatchflyLogger.info('Active patch from marker: #$num');
          return num.toString();
        }
      }
    } catch (e) {
      PatchflyLogger.warn('Marker file read failed: $e');
    }
    // Fallback to native (only works after plugin registers)
    try {
      const channel = MethodChannel('patchfly/apply');
      return await channel.invokeMethod<String>('getActivePatchNumber');
    } on PlatformException catch (e) {
      PatchflyLogger.warn('getActivePatchNumber failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// True if the native libpatchfly_updater.so is loaded.
  Future<bool> isUpdaterAvailable() async {
    try {
      const channel = MethodChannel('patchfly/apply');
      final r = await channel.invokeMethod<bool>('isUpdaterAvailable');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Convenience: check, download, and apply in one call.
  ///
  /// Skips download/apply if the device already has the active patch
  /// matching the latest one on the server (prevents restart loops).
  Future<PatchflyUpdate?> checkDownloadApply() async {
    final update = await checkForUpdate();
    if (update == null) return null;

    // Ask the native updater what patch is currently active.
    // If it matches the latest from server, skip — no point re-applying.
    try {
      final activeStr = await getActivePatchNumber();
      final activeNum = activeStr != null ? int.tryParse(activeStr) : null;
      if (activeNum != null && activeNum >= update.patchNumber) {
        PatchflyLogger.info(
            'Already on patch #$activeNum (server has #${update.patchNumber}) — skipping');
        return null;
      }
    } catch (_) {
      // If we can't read the active patch, proceed with download.
      // Better to re-apply than to miss an update.
    }

    final path = await download(update);
    await apply(path, patchNumber: update.patchNumber, sha256: update.sha256);
    return update;
  }

  // ---- Internals ----

  String _platformString() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Returns the file extension used for patches on the current platform.
  String _patchFileExtension() {
    if (Platform.isIOS) return '.patchfly';
    return '.so';
  }


  bool _verifySignature({
    required String messageHash,
    required String signatureB64,
    required ed.PublicKey publicKey,
  }) {
    try {
      final hashBytes = Uint8List.fromList(_hexToBytes(messageHash));
      final sigBytes = base64Decode(signatureB64);
      if (sigBytes.length != 64) return false;
      return ed.verify(publicKey, hashBytes, Uint8List.fromList(sigBytes));
    } catch (e) {
      PatchflyLogger.error('Signature verification error: $e');
      return false;
    }
  }

  Future<void> _recordEvent(String eventType, {PatchflyUpdate? update}) async {
    if (_config == null) return;
    try {
      await http.post(
        Uri.parse('${_config!.serverUrl}/api/v1/sdk/events'),
        headers: {
          'X-Patchfly-SDK-Key': _config!.sdkKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'eventType': eventType,
          'patchId': update?.patchId,
          'appVersion': _appVersion,
          'deviceId': _deviceId,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // best-effort
    }
  }

  static List<int> _hexToBytes(String hex) {
    if (hex.length % 2 != 0) throw FormatException('odd hex');
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
