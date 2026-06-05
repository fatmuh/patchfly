// `patchfly keys` — manage CLI API keys.

import 'dart:convert';
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
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('json', help: 'Output as JSON (for piping into jq etc.)')
      ..addCommand('list', _listParser())
      ..addCommand('create', _createSubParser())
      ..addCommand('revoke', _revokeSubParser());

    if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return;
    }
    final result = parser.parse(args);
    if (result['help'] == true) {
      _printUsage();
      return;
    }

    final cfg = await ConfigStore.load();
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );

    final asJson = result['json'] == true;
    final sub = result.command?.name;

    if (sub == null || sub == 'list') {
      await _list(api, asJson);
    } else if (sub == 'create') {
      await _create(api, result.command!, asJson);
    } else if (sub == 'revoke') {
      final rest = result.command!.rest;
      if (rest.isEmpty) {
        throw CliException('Usage: patchfly keys revoke <id-or-prefix>');
      }
      await _revoke(api, rest.first, asJson);
    } else {
      _printUsage();
    }
  }

  static ArgParser _listParser() => ArgParser();
  static ArgParser _revokeSubParser() => ArgParser();

  static ArgParser _createSubParser() => ArgParser()
    ..addOption('name', help: 'Name for this key (e.g. "Work laptop") (required)')
    ..addOption('expires-in-days', help: 'Expire after N days (optional)');

  void _printUsage() {
    print('''
patchfly keys — manage CLI API keys

Usage:
  patchfly keys <subcommand> [options]

Subcommands:
  list                    List all your CLI API keys
  create [options]        Create a new API key
  revoke <id-or-prefix>   Revoke an API key (irreversible)

Common options:
  --json                  Output as JSON
  -h, --help              Show this help

Options for `create`:
      --name <name>       Friendly name for this key (required)
      --expires-in-days   Optional: expire after N days

Examples:
  # List all keys
  patchfly keys list

  # Create a new key
  patchfly keys create --name "Work laptop"
  patchfly keys create --name "CI runner" --expires-in-days 90

  # Revoke a key
  patchfly keys revoke pfk_Work  # by prefix
  patchfly keys revoke <key-id>  # by full ID

  # Save a new key (printed once, never again)
  patchfly keys create --name "Laptop 2" | tee new-key.txt
  patchfly login --api-key \$(cat new-key.txt)
''');
  }

  Future<void> _list(ApiClient api, bool asJson) async {
    final res = await api.get('/api/v1/keys');
    final keys = (res as Map)['apiKeys'] as List;
    if (keys.isEmpty) {
      print('No API keys yet. Run `patchfly keys create --name "My Laptop"`.');
      return;
    }
    if (asJson) {
      print(const JsonEncoder.withIndent('  ')
          .convert({'count': keys.length, 'apiKeys': keys}));
      return;
    }
    print('API keys:');
    for (final k in keys) {
      final last = k['lastUsedAt'] ?? '(never)';
      print('  ${k['keyPrefix']}...  ${k['name']}  last used: $last');
    }
  }

  Future<void> _create(ApiClient api, ArgResults args, bool asJson) async {
    final name = args['name'] as String?;
    if (name == null) {
      throw CliException('--name is required',
          hint: 'patchfly keys create --name "Work laptop"');
    }
    final body = <String, dynamic>{'name': name};
    final days = args['expires-in-days'];
    if (days != null) body['expiresInDays'] = int.parse(days as String);

    final res = await api.post('/api/v1/keys', body);
    final key = (res as Map)['plaintext'] as String;

    if (asJson) {
      print(const JsonEncoder.withIndent('  ').convert(res));
      return;
    }

    print('✓ Created API key: $key');
    print('');
    print('Save this now. You will not be able to see it again.');
    print('To use it:');
    print('  patchfly login --api-key $key');
  }

  Future<void> _revoke(ApiClient api, String target, bool asJson) async {
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
    if (asJson) {
      print(const JsonEncoder.withIndent('  ').convert({'revoked': match}));
      return;
    }
    print('✓ Revoked key ${match['keyPrefix']}...');
  }
}
