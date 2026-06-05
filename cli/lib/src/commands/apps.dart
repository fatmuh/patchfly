// `patchfly apps` — manage your apps on the Patchfly server.

import 'dart:convert';
import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class AppsCommand implements CommandRunner {
  @override
  String get name => 'apps';
  @override
  String get description => 'Manage your apps (list, create, get, delete)';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('json', help: 'Output as JSON (for piping into jq etc.)')
      ..addCommand('list', _listParser())
      ..addCommand('create', _createSubParser())
      ..addCommand('get', _getParser())
      ..addCommand('delete', _deleteParser());

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
    final cmd = result.command?.name;

    if (cmd == null || cmd == 'list') {
      await _list(api, asJson);
    } else if (cmd == 'create') {
      await _create(api, result.command!, asJson);
    } else if (cmd == 'get') {
      final rest = result.command!.rest;
      if (rest.isEmpty) {
        throw CliException('Usage: patchfly apps get <slug>');
      }
      await _get(api, rest.first, asJson);
    } else if (cmd == 'delete') {
      final rest = result.command!.rest;
      if (rest.isEmpty) {
        throw CliException('Usage: patchfly apps delete <slug>');
      }
      await _delete(api, rest.first);
    } else {
      _printUsage();
    }
  }

  static ArgParser _listParser() => ArgParser();
  static ArgParser _getParser() => ArgParser();
  static ArgParser _deleteParser() => ArgParser();

  static ArgParser _createSubParser() => ArgParser()
    ..addOption('slug', help: 'Reverse-DNS slug, e.g. com.acme.myapp (required)')
    ..addOption('name', help: 'Display name (required)')
    ..addOption('platform',
        allowed: ['android', 'ios', 'all'], defaultsTo: 'android',
        help: 'Target platform');

  void _printUsage() {
    print('''
patchfly apps — manage your apps on the Patchfly server

Usage:
  patchfly apps <subcommand> [options]

Subcommands:
  list                    List every app you own
  create [options]        Register a new app on the server
  get <slug>              Show full details of one app (incl. SDK key prefix)
  delete <slug>           Delete an app (irreversible)

Common options:
  --json                  Output as JSON
  -h, --help              Show this help

Options for `create`:
      --slug <slug>       Reverse-DNS slug, e.g. com.acme.myapp (required)
      --name <name>       Display name (required)
      --platform <name>   android | ios | all (default: android)

Examples:
  # List apps
  patchfly apps list

  # Register a new app
  patchfly apps create --slug com.acme.myapp --name "Acme App"

  # Get an app's details (including SDK key prefix)
  patchfly apps get com.acme.myapp

  # JSON for piping
  patchfly apps list --json | jq '.apps[] | .slug'

  # Delete (irreversible!)
  patchfly apps delete com.acme.myapp
''');
  }

  Future<void> _list(ApiClient api, bool asJson) async {
    final res = await api.get('/api/v1/apps');
    final apps = (res as Map)['apps'] as List;
    if (apps.isEmpty) {
      print('No apps. Run `patchfly apps create --slug com.your.app --name "Your App"`.');
      return;
    }
    if (asJson) {
      print(const JsonEncoder.withIndent('  ')
          .convert({'count': apps.length, 'apps': apps}));
      return;
    }
    print('${'SLUG'.padRight(40)} ${'NAME'.padRight(30)} ${'PLATFORM'.padRight(10)} ${'SDK KEY'.padRight(15)} ID');
    for (final a in apps) {
      print('${a['slug'].toString().padRight(40)} ${a['name'].toString().padRight(30)} ${a['platform'].toString().padRight(10)} ${a['sdkKeyPrefix'].toString().padRight(15)} ${a['id']}');
    }
  }

  Future<void> _create(ApiClient api, ArgResults args, bool asJson) async {
    final slug = args['slug'] as String?;
    final name = args['name'] as String?;
    if (slug == null || name == null) {
      throw CliException('--slug and --name are required',
          hint: 'patchfly apps create --slug <slug> --name "Name"');
    }
    final res = await api.post('/api/v1/apps', {
      'slug': slug,
      'name': name,
      'platform': args['platform'] ?? 'android',
    });
    final app = (res as Map)['app'] as Map;
    final sdkKey = res['sdkKey'] as String;

    if (asJson) {
      print(const JsonEncoder.withIndent('  ').convert({'app': app, 'sdkKey': sdkKey}));
      return;
    }

    print('✓ App created: ${app['slug']} (${app['id']})');
    print('');
    print('SDK key (save now, you cannot see it again):');
    print('  $sdkKey');
    print('');
    print('Put this in your Flutter app (e.g. main.dart):');
    print('  Patchfly.init(sdkKey: "$sdkKey");');
  }

  Future<void> _get(ApiClient api, String slug, bool asJson) async {
    final list = await api.get('/api/v1/apps') as Map;
    final apps = list['apps'] as List;
    final app = apps.firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) throw CliException('No app with slug: $slug');

    if (asJson) {
      print(const JsonEncoder.withIndent('  ').convert(app));
      return;
    }

    print('ID:        ${app['id']}');
    print('Slug:      ${app['slug']}');
    print('Name:      ${app['name']}');
    print('Platform:  ${app['platform']}');
    print('SDK key:   ${app['sdkKeyPrefix']}...');
    if (app['createdAt'] != null) {
      print('Created:   ${app['createdAt']}');
    }
  }

  Future<void> _delete(ApiClient api, String slug) async {
    final list = await api.get('/api/v1/apps') as Map;
    final apps = list['apps'] as List;
    final app = apps.firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) throw CliException('No app with slug: $slug');
    await api.delete('/api/v1/apps/${app['id']}');
    print('✓ Deleted app $slug');
  }
}
