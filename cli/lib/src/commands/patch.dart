// `patchfly patch` — build a patch and upload it.
//
// Strategy:
//   1. Run `flutter build apk --release` to build the APK
//   2. Extract libapp.so from the APK
//   3. Hash it, upload to server
//   4. The user has the patch live for that release

import 'dart:io';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class PatchCommand implements CommandRunner {
  @override
  String get name => 'patch';
  @override
  String get description =>
      'Build a release & upload as a patch to the active release';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addOption('config', defaultsTo: 'patchfly.yaml', help: 'Path to patchfly.yaml')
      ..addOption('release', help: 'Specific release ID (default: latest active)')
      ..addOption('abi', help: 'Target ABI (arm64-v8a, armeabi-v7a, x86_64)')
      ..addOption('channel', help: 'Channel to patch (stable/beta/...)')
      ..addOption('rollout',
          help: 'Rollout percent (0-100). Default: 100 (full)')
      ..addOption('min-app-version', help: 'Min app version required to receive this patch')
      ..addOption('max-app-version')
      ..addFlag('skip-build', help: 'Skip `flutter build`, use existing APK')
      ..addFlag('dry-run', help: 'Compute everything but do not upload')
      ..addFlag('no-activate', negatable: false, help: 'Upload but don\'t activate');
    final result = parser.parse(args);

    final cwd = Directory.current;
    final configFile = File(p.join(cwd.path, result['config'] as String));
    if (!await configFile.exists()) {
      throw CliException(
          'patchfly.yaml not found. Run `patchfly init` first.',
          hint: 'patchfly init');
    }
    final yaml = loadYaml(await configFile.readAsString()) as YamlMap;

    final appSlug = yaml['app']?['slug'] as String?;
    if (appSlug == null || appSlug == '<your-app-slug>') {
      throw CliException('app.slug is not set in patchfly.yaml');
    }
    final defaults = yaml['defaults'] as YamlMap?;
    final build = yaml['build'] as YamlMap?;
    final apkPath = build?['apk_path'] as String?;
    if (apkPath == null) {
      throw CliException('build.apk_path is not set in patchfly.yaml');
    }

    final channel = (result['channel'] as String?) ??
        (defaults?['channel'] as String? ?? 'stable');
    final abi = (result['abi'] as String?) ??
        (defaults?['abi'] as String? ?? 'arm64-v8a');

    // 1. Auth & resolve app
    final cfg = await ConfigStore.load();
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );
    final apps = (await api.get('/api/v1/apps') as Map)['apps'] as List;
    final app = apps.firstWhere((a) => a['slug'] == appSlug, orElse: () => null);
    if (app == null) {
      throw CliException('No app registered with slug "$appSlug" on this server',
          hint: 'patchfly apps create --slug $appSlug --name "..."');
    }

    // 2. Find or create release
    String releaseId = (result['release'] as String?) ?? '';
    if (releaseId.isEmpty) {
      final rels = (await api.get('/api/v1/apps/${app['id']}/releases') as Map)['releases']
          as List;
      // Find active release on this channel
      final active = rels.firstWhere(
        (r) => r['channelName'] == channel && r['isActive'] == true,
        orElse: () => null,
      );
      if (active == null) {
        throw CliException(
            'No active release for channel "$channel". Create one first:',
            hint: 'patchfly releases create --app $appSlug --version <v> --channel $channel');
      }
      releaseId = active['id'] as String;
    }

    // 3. Build
    if (!(result['skip-build'] as bool)) {
      print('Building Flutter APK (release)...');
      final buildRes = await Process.run('flutter', [
        'build', 'apk',
        '--release',
        '--target-platform', _abiToPlatform(abi),
      ]);
      if (buildRes.exitCode != 0) {
        print(buildRes.stdout);
        print(buildRes.stderr);
        throw CliException('flutter build failed');
      }
    } else {
      print('Skipping build, using existing APK');
    }

    final absApk = p.isAbsolute(apkPath) ? apkPath : p.join(cwd.path, apkPath);
    final apk = File(absApk);
    if (!await apk.exists()) {
      throw CliException('APK not found: $absApk');
    }

    // 4. Extract libapp.so from APK (it's a zip)
    final extractDir = await Directory.systemTemp.createTemp('patchfly_patch_');
    print('Extracting libapp.so for $abi...');
    final libapp = await _extractLibAppSo(apk, abi, extractDir);
    final libappSize = await libapp.length();

    // 5. Hash
    final hash = sha256.convert(await libapp.readAsBytes()).toString();
    print('libapp.so: ${_formatBytes(libappSize)}, sha256=$hash');

    // 6. Upload
    if (result['dry-run'] as bool) {
      print('Dry run: would upload $absApk → $libapp (${_formatBytes(libappSize)})');
      return;
    }

    print('Uploading patch...');
    final res = await api.uploadMultipart(
      '/api/v1/releases/$releaseId/patches',
      file: libapp,
      fieldName: 'file',
      sha256: hash,
      rolloutPercent: int.tryParse((result['rollout'] as String?) ?? ''),
      minAppVersion: result['min-app-version'] as String?,
      maxAppVersion: result['max-app-version'] as String?,
      activate: !(result['no-activate'] as bool),
    );
    final patch = (res as Map)['patch'] as Map;
    print('✓ Patch #${patch['patchNumber']} uploaded (${_formatBytes(patch['sizeBytes'])})');
    print('  ID: ${patch['id']}');
    if (patch['isActive'] == true) {
      print('  Status: ACTIVE (live for all matching devices)');
    } else {
      print('  Status: inactive (use `patchfly promote` to activate)');
    }
  }

  String _abiToPlatform(String abi) {
    switch (abi) {
      case 'arm64-v8a':
        return 'android-arm64';
      case 'armeabi-v7a':
        return 'android-arm';
      case 'x86_64':
        return 'android-x64';
    }
    return 'android-arm64';
  }

  Future<File> _extractLibAppSo(
      File apk, String abi, Directory dest) async {
    // We shell out to `unzip` because doing zip in pure Dart is non-trivial
    // and we want to keep this MVP small. (TODO: use package:archive)
    final archDir = Directory(p.join(dest.path, abi))..createSync();
    final res = await Process.run('unzip', [
      '-o',
      '-j',
      apk.path,
      'lib/$abi/libapp.so',
      '-d',
      archDir.path,
    ]);
    if (res.exitCode != 0) {
      print(res.stdout);
      print(res.stderr);
      throw CliException('Failed to extract libapp.so from APK. Is unzip installed?');
    }
    final out = File(p.join(archDir.path, 'libapp.so'));
    if (!await out.exists()) {
      throw CliException(
          'libapp.so not found in APK for ABI $abi. Make sure the build included this ABI.');
    }
    return out;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
