// `patchfly doctor` — sanity checks.

import 'dart:io';
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
    if (args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return;
    }

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

    // 2. unzip
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

    // 3. patchfly.yaml
    final cfgFile = File('patchfly.yaml');
    if (cfgFile.existsSync()) {
      print('✓ patchfly.yaml found');
    } else {
      print('⚠ patchfly.yaml not found. Run `patchfly init` first.');
    }

    // 4. server connectivity
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

    // 5. auth
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
  patchfly doctor

Checks:
  - flutter installed
  - unzip available
  - patchfly.yaml exists
  - server reachable (/health)
  - logged in (JWT or API key)

Examples:
  patchfly doctor
''');
  }
}

class _CmdResult {
  final bool ok;
  final String stdout;
  final String stderr;
  _CmdResult(this.ok, this.stdout, this.stderr);
}
