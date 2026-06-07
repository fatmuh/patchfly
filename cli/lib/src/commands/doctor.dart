// `patchfly doctor` — sanity checks.

import 'dart:io';
import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class DoctorCommand implements CommandRunner {
  @override
  String get name => 'doctor';
  @override
  String get description => 'Check environment, server connectivity, etc.';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addOption('platform',
          allowed: ['android', 'ios', 'all'],
          defaultsTo: 'all',
          help: 'Which platform checks to run: android, ios, or all');

    final result = parser.parse(args);
    if (result['help'] == true || args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return;
    }

    final platform = result['platform'] as String;
    final checkAndroid = platform == 'android' || platform == 'all';
    final checkIos = platform == 'ios' || platform == 'all';

    print('Patchfly doctor\n');

    var problems = 0;

    // 1. flutter
    final flutter = await _tryCmd('flutter', ['--version']);
    if (flutter.ok) {
      final firstLine = flutter.stdout.split('\n').first;
      print('✓ flutter: $firstLine');
    } else {
      print('✗ flutter: not found in PATH (or failed)');
      print('    Install Flutter: https://docs.flutter.dev/get-started/install');
      problems++;
    }

    // 2. Android-specific checks
    if (checkAndroid) {
      print('\n--- Android ---');

      // unzip (needed for APK extraction)
      final unzip = await _tryCmd('unzip', ['-v']);
      if (unzip.ok) {
        print('✓ unzip: available');
      } else {
        print('✗ unzip: not found. Needed for extracting libapp.so from APK.');
        if (Platform.isWindows) {
          print('    Windows: bundled with Git for Windows. Install: winget install Git.Git');
        } else {
          print('    macOS: brew install unzip');
          print('    Linux: sudo apt-get install unzip');
        }
        problems++;
      }
    }

    // 3. iOS-specific checks
    if (checkIos) {
      print('\n--- iOS ---');

      // Xcode
      final xcode = await _tryCmd('xcodebuild', ['-version']);
      if (xcode.ok) {
        final firstLine = xcode.stdout.split('\n').first;
        print('✓ Xcode: $firstLine');
      } else {
        print('✗ Xcode: not found. Required for iOS builds.');
        print('    Install from the Mac App Store or https://developer.apple.com/xcode/');
        problems++;
      }

      // CocoaPods
      final pods = await _tryCmd('pod', ['--version']);
      if (pods.ok) {
        final ver = pods.stdout.trim();
        print('✓ CocoaPods: $ver');
      } else {
        print('✗ CocoaPods: not found. Required for iOS dependency management.');
        print('    Install: sudo gem install cocoapods');
        problems++;
      }

      // Rust toolchain (for building native updater)
      final rustc = await _tryCmd('rustc', ['--version']);
      if (rustc.ok) {
        final ver = rustc.stdout.trim();
        print('✓ Rust: $ver');
      } else {
        print('✗ Rust: not found. Required for building the native iOS updater.');
        print('    Install: curl --proto \'=https\' --tlsv1.2 -sSf https://sh.rustup.rs | sh');
        problems++;
      }

      // iOS Rust targets
      if (rustc.ok) {
        final targets = await _tryCmd('rustup', ['target', 'list', '--installed']);
        if (targets.ok) {
          final lines = targets.stdout
              .split('\n')
              .where((l) => l.contains('apple'))
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          if (lines.isNotEmpty) {
            print('✓ iOS Rust targets: ${lines.join(', ')}');
          } else {
            print('⚠ No Apple Rust targets installed. You may need:');
            print('    rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim');
            problems++;
          }
        }
      }
    }

    // 4. patchfly.yaml
    print('\n--- General ---');
    final cfgFile = File('patchfly.yaml');
    if (cfgFile.existsSync()) {
      print('✓ patchfly.yaml found');
    } else {
      print('⚠ patchfly.yaml not found. Run `patchfly init` first.');
    }

    // 5. server connectivity
    final cfg = await ConfigStore.load();
    final server = ConfigStore.resolveServer(cfg);
    print('\nServer: $server');
    try {
      final api = ApiClient(baseUrl: server, authHeader: () => cfg.authHeader);
      final res = await api.get('/health');
      if (res is Map && res['status'] == 'ok') {
        print('✓ Server reachable');
        if (res['version'] != null) print('  Version: ${res['version']}');
      } else {
        print('⚠ Server responded but health check failed: $res');
        problems++;
      }
    } catch (e) {
      print('✗ Cannot reach server: $e');
      problems++;
    }

    // 6. auth
    if (cfg.token == null && cfg.apiKey == null) {
      print('✗ Not logged in. Run `patchfly login`.');
      problems++;
    } else {
      print('✓ Auth: ${cfg.apiKey != null ? "API key" : "JWT"}');
      if (cfg.userEmail != null) print('  Email: ${cfg.userEmail}');
    }

    print('');
    if (problems == 0) {
      print('All checks passed. Ready to ship patches.');
    } else {
      print('$problems problem(s) found. See hints above.');
    }
  }

  Future<_CmdResult> _tryCmd(String cmd, List<String> args) async {
    try {
      // On Windows, prefer cmd.exe for built-ins; for tools, try direct.
      final res = await Process.run(cmd, args,
          runInShell: Platform.isWindows);
      return _CmdResult(res.exitCode == 0, res.stdout.toString(),
          res.stderr.toString());
    } catch (_) {
      return _CmdResult(false, '', '');
    }
  }

  void _printUsage() {
    print('''
patchfly doctor — check environment, server connectivity, etc.

Usage:
  patchfly doctor [options]

Options:
      --platform <name>  Which platform checks to run: android | ios | all (default: all)
  -h, --help             Show this help

Checks (all platforms):
  - flutter installed
  - patchfly.yaml exists
  - server reachable (/health)
  - logged in (JWT or API key)

Android-specific:
  - unzip available (for APK extraction)

iOS-specific:
  - Xcode installed
  - CocoaPods installed
  - Rust toolchain (for native updater)
  - Apple Rust targets installed

Examples:
  patchfly doctor
  patchfly doctor --platform android
  patchfly doctor --platform ios
''');
  }
}

class _CmdResult {
  final bool ok;
  final String stdout;
  final String stderr;
  _CmdResult(this.ok, this.stdout, this.stderr);
}
