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
    print('Patchfly doctor\n');

    var problems = 0;

    // 1. flutter
    final flutter = await Process.run('flutter', ['--version']);
    if (flutter.exitCode == 0) {
      final firstLine = (flutter.stdout as String).split('\n').first;
      print('✓ flutter: $firstLine');
    } else {
      print('✗ flutter: not found in PATH');
      problems++;
    }

    // 2. unzip
    final unzip = await Process.run('unzip', ['-v']);
    if (unzip.exitCode == 0) {
      print('✓ unzip: available');
    } else {
      print('✗ unzip: not found. Needed for extracting libapp.so from APK.');
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
      } else {
        print('⚠ Server responded but health check failed: $res');
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
    }

    if (problems == 0) {
      print('\nAll checks passed.');
    } else {
      print('\n$problems problem(s) found.');
    }
  }
}
