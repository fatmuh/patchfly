// `patchfly promote` — activate an existing patch.

import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class PromoteCommand implements CommandRunner {
  @override
  String get name => 'promote';
  @override
  String get description =>
      'Activate a patch (make it live for matching devices)';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addOption('app', help: 'App slug')
      ..addOption('release', help: 'Release ID')
      ..addOption('patch', help: 'Patch number (e.g. 3)');
    final result = parser.parse(args);

    final slug = result['app'] as String?;
    final releaseId = result['release'] as String?;
    final patchNumStr = result['patch'] as String?;
    if (slug == null || releaseId == null || patchNumStr == null) {
      throw CliException('--app, --release, and --patch are all required');
    }
    final patchNum = int.parse(patchNumStr);

    final cfg = await ConfigStore.load();
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );

    final patches = (await api.get(
            '/api/v1/releases/$releaseId/patches') as Map)['patches'] as List;
    final patch = patches.firstWhere(
      (p) => p['patchNumber'] == patchNum,
      orElse: () => null,
    );
    if (patch == null) {
      throw CliException('No patch #$patchNum on release $releaseId');
    }
    await api.post('/api/v1/patches/${patch['id']}/activate');
    print('✓ Patch #$patchNum is now active');
  }
}
