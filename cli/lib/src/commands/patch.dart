// `patchfly patch` — build a patch and upload it.
//
// Strategy:
//   Android:
//     1. Run `flutter build apk --release` to build the APK
//     2. Extract libapp.so from the APK
//     3. Hash it, upload to server
//   iOS:
//     1. Run `flutter build ios --release --no-codesign` to build the IPA artefacts
//     2. Extract App binary from App.framework
//     3. Hash it, upload to server

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
    if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return;
    }

    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addOption('platform',
          allowed: ['android', 'ios'],
          defaultsTo: 'android',
          help: 'Target platform (android or ios)')
      ..addOption('config', defaultsTo: 'patchfly.yaml', help: 'Path to patchfly.yaml')
      ..addOption('app', help: 'App slug (overrides app.slug in patchfly.yaml)')
      ..addOption('release', help: 'Specific release ID (default: latest active)')
      ..addOption('abi', help: 'Target ABI (arm64-v8a, armeabi-v7a, x86_64). Android only.')
      ..addOption('channel', help: 'Channel to patch (stable/beta/...)')
      ..addOption('rollout',
          help: 'Rollout percent (0-100). Default: 100 (full)')
      ..addOption('min-app-version', help: 'Min app version required to receive this patch')
      ..addOption('max-app-version')
      ..addFlag('skip-build', help: 'Skip `flutter build`, use existing build output')
      ..addFlag('dry-run', help: 'Compute everything but do not upload')
      ..addFlag('no-activate', negatable: false, help: 'Upload but don\'t activate');
    final result = parser.parse(args);
    if (result['help'] == true) {
      _printUsage();
      return;
    }

    final cwd = Directory.current;
    final configFile = File(p.join(cwd.path, result['config'] as String));
    if (!await configFile.exists()) {
      throw CliException(
          'patchfly.yaml not found. Run `patchfly init` first.',
          hint: 'patchfly init');
    }
    // The project root is wherever patchfly.yaml lives, NOT the current
    // process CWD. The CLI may be invoked from anywhere.
    final projectDir = configFile.parent.path;
    final yaml = loadYaml(await configFile.readAsString()) as YamlMap;

    // CLI flag --app overrides patchfly.yaml's app.slug
    final appSlug = (result['app'] as String?) ??
        (yaml['app']?['slug'] as String?);
    if (appSlug == null || appSlug == '<your-app-slug>') {
      throw CliException(
          'No app specified. Either set app.slug in patchfly.yaml or pass --app <slug>');
    }
    final platform = result['platform'] as String;
    final defaults = yaml['defaults'] as YamlMap?;
    final build = yaml['build'] as YamlMap?;

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
    final flutterCmd = Platform.isWindows ? 'flutter.bat' : 'flutter';
    if (!(result['skip-build'] as bool)) {
      if (platform == 'ios') {
        print('Building Flutter iOS (release, no-codesign)...');
        final buildRes = await Process.run(
          flutterCmd,
          ['build', 'ios', '--release', '--no-codesign'],
          workingDirectory: projectDir,
        );
        if (buildRes.exitCode != 0) {
          stdout.write(buildRes.stdout);
          stderr.write(buildRes.stderr);
          throw CliException('flutter build ios failed');
        }
      } else {
        print('Building Flutter APK (release)...');
        // The build MUST run from the project directory (where pubspec.yaml
        // and the Flutter project live), not from wherever the CLI is invoked.
        final buildRes = await Process.run(
          flutterCmd,
          [
            'build', 'apk',
            '--release',
            '--target-platform', _abiToPlatform(abi),
          ],
          workingDirectory: projectDir,
        );
        if (buildRes.exitCode != 0) {
          stdout.write(buildRes.stdout);
          stderr.write(buildRes.stderr);
          throw CliException('flutter build failed');
        }
      }
    } else {
      print('Skipping build, using existing build output');
    }

    // 4. Extract the compiled binary
    final extractDir = await Directory.systemTemp.createTemp('patchfly_patch_');
    late File patchFile;

    if (platform == 'ios') {
      // iOS: extract App binary from App.framework
      final iosAppPath = build?['ios_app_path'] as String?;
      if (iosAppPath != null && (result['skip-build'] as bool)) {
        // Use configured path directly
        final absPath = p.isAbsolute(iosAppPath) ? iosAppPath : p.join(projectDir, iosAppPath);
        patchFile = File(absPath);
        if (!await patchFile.exists()) {
          throw CliException('iOS App binary not found: $absPath');
        }
      } else {
        print('Extracting App binary from iOS build...');
        patchFile = await _extractIosApp(Directory(projectDir), extractDir);
      }
    } else {
      // Android: extract libapp.so from APK
      final apkPath = build?['apk_path'] as String?;
      if (apkPath == null) {
        throw CliException('build.apk_path is not set in patchfly.yaml');
      }
      final absApk = p.isAbsolute(apkPath) ? apkPath : p.join(projectDir, apkPath);
      final apk = File(absApk);
      if (!await apk.exists()) {
        throw CliException('APK not found: $absApk');
      }
      print('Extracting libapp.so for $abi...');
      patchFile = await _extractLibAppSo(apk, abi, extractDir);
    }

    final patchSize = await patchFile.length();

    // 5. Hash
    final hash = sha256.convert(await patchFile.readAsBytes()).toString();
    final label = platform == 'ios' ? 'App' : 'libapp.so';
    print('$label: ${_formatBytes(patchSize)}, sha256=$hash');

    // 6. Upload
    if (result['dry-run'] as bool) {
      print('Dry run: would upload $label (${_formatBytes(patchSize)})');
      return;
    }

    print('Uploading patch...');
    final res = await api.uploadMultipart(
      '/api/v1/releases/$releaseId/patches',
      file: patchFile,
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

  void _printUsage() {
    print('''
patchfly patch — build a release & upload as a patch

Usage:
  patchfly patch [options]

Options:
      --platform <name>    Target platform: android | ios (default: android)
      --config <path>      Path to patchfly.yaml (default: ./patchfly.yaml)
  -a, --app <slug>         App slug (overrides app.slug in yaml)
      --release <id>       Specific release ID (default: latest active)
      --abi <name>         Target ABI: arm64-v8a | armeabi-v7a | x86_64 (Android only)
      --channel <name>     Channel to patch: stable | beta | internal | alpha
      --rollout <0-100>    Rollout percent (default: 100 = full)
      --min-app-version <v>  Only deliver to apps with version >= this
      --max-app-version <v>  Only deliver to apps with version <= this
      --skip-build          Skip `flutter build`, use existing build output
      --dry-run             Build, but don't upload
      --no-activate         Upload but don't activate (use `patches promote`)
  -h, --help                Show this help

What it does (Android):
  1. Run `flutter build apk --release` (or use existing APK with --skip-build)
  2. Extract libapp.so from the APK
  3. Hash it, upload to server
  4. Activate it (unless --no-activate)

What it does (iOS):
  1. Run `flutter build ios --release --no-codesign` (or use existing with --skip-build)
  2. Extract App binary from App.framework
  3. Hash it, upload to server
  4. Activate it (unless --no-activate)

Examples:
  # Android: default build + upload + activate
  patchfly patch --app com.example.test

  # iOS: build + upload + activate
  patchfly patch --platform ios --app com.example.test

  # Build for a different ABI (Android only)
  patchfly patch --app com.example.test --abi x86_64

  # Staged rollout (start at 25%)
  patchfly patch --app com.example.test --rollout 25

  # Upload but don't activate yet
  patchfly patch --app com.example.test --no-activate
  patchfly patches promote 1 --app com.example.test   # activate later

  # Use an existing build (no rebuild)
  patchfly patch --app com.example.test --skip-build

  # Dry run (verify config without uploading)
  patchfly patch --app com.example.test --dry-run
''');
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

  Future<File> _extractIosApp(Directory projectDir, Directory dest) async {
    // iOS build output: build/ios/iphoneos/Runner.app/Frameworks/App.framework/App
    final appBinary = File(p.join(projectDir.path,
        'build/ios/iphoneos/Runner.app/Frameworks/App.framework/App'));
    if (!await appBinary.exists()) {
      throw CliException(
          'App.framework/App not found. Run `flutter build ios --release --no-codesign` first.');
    }
    final destFile = File(p.join(dest.path, 'App'));
    await appBinary.copy(destFile.path);
    return destFile;
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
