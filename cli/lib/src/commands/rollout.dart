// `patchfly rollout` — adjust rollout percentage for staged rollouts.

import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class RolloutCommand implements CommandRunner {
  @override
  String get name => 'rollout';
  @override
  String get description =>
      'Adjust rollout percentage for the active patch (staged rollouts)';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addOption('patch', help: 'Patch ID')
      ..addOption('percent',
          help: 'New rollout percent (0-100). 0 = effectively rollback');
    final result = parser.parse(args);

    final patchId = result['patch'] as String?;
    final percent = int.tryParse((result['percent'] as String?) ?? '');
    if (patchId == null || percent == null) {
      throw CliException('--patch and --percent are required');
    }
    if (percent < 0 || percent > 100) {
      throw CliException('--percent must be 0-100');
    }

    final cfg = await ConfigStore.load();
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );

    final res = await api.post(
        '/api/v1/patches/$patchId/rollout', {'percent': percent});
    final patch = (res as Map)['patch'] as Map;
    print('✓ Rollout set to $percent% for patch #${patch['patchNumber']}');
  }
}
