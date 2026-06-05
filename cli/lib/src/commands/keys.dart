// `patchfly keys` — manage CLI API keys.

import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class KeysCommand implements CommandRunner {
  @override
  String get name => 'keys';
  @override
  String get description => 'Manage CLI API keys';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addCommand('list', _emptySubParser())
      ..addCommand('create', _createSubParser())
      ..addCommand('revoke', _emptySubParser());
    final result = parser.parse(args);

    final cfg = await ConfigStore.load();
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );

    if (result.command == null || result.command!.name == 'list') {
      await _list(api);
    } else if (result.command!.name == 'create') {
      await _create(api, result.command!);
    } else if (result.command!.name == 'revoke') {
      await _revoke(api, result.command!);
    } else {
      print('Usage: patchfly keys <list|create|revoke>');
    }
  }

  static ArgParser _emptySubParser() => ArgParser();

  static ArgParser _createSubParser() => ArgParser()
    ..addOption('name', help: 'Name for this key (e.g. "Work laptop")')
    ..addOption('expires-in-days', help: 'Expire after N days (optional)');

  Future<void> _list(ApiClient api) async {
    final res = await api.get('/api/v1/keys');
    final keys = (res as Map)['apiKeys'] as List;
    if (keys.isEmpty) {
      print('No API keys yet. Run `patchfly keys create --name "My Laptop"`.');
      return;
    }
    print('API keys:');
    for (final k in keys) {
      final last = k['lastUsedAt'] ?? '(never)';
      print('  ${k['keyPrefix']}...  ${k['name']}  last used: $last');
    }
  }

  Future<void> _create(ApiClient api, ArgResults args) async {
    final name = args['name'] as String?;
    if (name == null) {
      throw CliException('--name is required');
    }
    final body = <String, dynamic>{'name': name};
    final days = args['expires-in-days'];
    if (days != null) body['expiresInDays'] = int.parse(days as String);

    final res = await api.post('/api/v1/keys', body);
    final key = (res as Map)['plaintext'] as String;
    print('✓ Created API key: $key');
    print('');
    print('Save this now. You will not be able to see it again.');
    print('To use it:');
    print('  patchfly login --api-key $key');
  }

  Future<void> _revoke(ApiClient api, ArgResults args) async {
    if (args.rest.isEmpty) {
      throw CliException('Usage: patchfly keys revoke <id-or-prefix>');
    }
    final target = args.rest.first;
    final list = await api.get('/api/v1/keys') as Map;
    final keys = list['apiKeys'] as List;
    final match = keys.firstWhere(
      (k) => (k['id'] == target) || (k['keyPrefix'] == target),
      orElse: () => null,
    );
    if (match == null) {
      throw CliException('No key with id or prefix: $target');
    }
    await api.delete('/api/v1/keys/${match['id']}');
    print('✓ Revoked key ${match['keyPrefix']}...');
  }
}
