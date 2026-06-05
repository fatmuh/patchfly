// `patchfly releases` — manage releases for an app.

import 'dart:convert';
import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class ReleasesCommand implements CommandRunner {
  @override
  String get name => 'releases';
  @override
  String get description => 'Manage releases (list, create)';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('json', help: 'Output as JSON (for piping into jq etc.)')
      ..addCommand('list', _listParser())
      ..addCommand('create', _createSubParser());

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
      await _list(api, result.command!, asJson);
    } else if (cmd == 'create') {
      await _create(api, result.command!, asJson);
    } else {
      _printUsage();
    }
  }

  static ArgParser _listParser() => ArgParser()
    ..addOption('app', abbr: 'a',
        help: 'App slug (or pass it as a positional argument)')
    ..addFlag('all', help: 'List releases for every app you own');

  static ArgParser _createSubParser() => ArgParser()
    ..addOption('app', abbr: 'a', help: 'App slug (required)')
    ..addOption('version', help: 'Version string, e.g. 1.4.2+15 (required)')
    ..addOption('channel',
        allowed: ['stable', 'beta', 'internal', 'alpha'],
        defaultsTo: 'stable',
        help: 'Release channel')
    ..addOption('notes', help: 'Release notes');

  void _printUsage() {
    print('''
patchfly releases — manage releases for an app

Usage:
  patchfly releases <subcommand> [options]

Subcommands:
  list [options]          List releases for an app (or all apps)
  create [options]        Create a new release

Common options:
  --json                  Output as JSON
  -h, --help              Show this help

Options for `list`:
  -a, --app <slug>        App slug (or pass as positional)
      --all               List releases for every app you own

Options for `create`:
  -a, --app <slug>        App slug (required)
      --version <v>       Version string, e.g. 1.4.2+15 (required)
      --channel <name>    stable | beta | internal | alpha (default: stable)
      --notes <text>      Release notes

Examples:
  # List releases for a specific app
  patchfly releases list --app com.example.test
  patchfly releases list com.example.test           # same, positional slug

  # List every release across all your apps
  patchfly releases list --all

  # JSON output
  patchfly releases list --app com.example.test --json

  # Create a new release
  patchfly releases create --app com.example.test --version 1.2.0+3 --channel stable --notes "Bug fixes"

  # Get the latest release ID for use with `patches`
  patchfly releases list --app com.example.test --json | jq -r '.releases[0].id'
''');
  }

  Future<void> _list(ApiClient api, ArgResults args, bool asJson) async {
    final all = args['all'] as bool;
    var slug = args['app'] as String?;
    if (slug == null && args.rest.isNotEmpty) slug = args.rest.first;

    final apps = (await api.get('/api/v1/apps') as Map)['apps'] as List;
    if (apps.isEmpty) {
      print('No apps yet. Run `patchfly apps create --slug ... --name ...`.');
      return;
    }

    if (!all && slug == null) {
      throw CliException('App slug required',
          hint: 'patchfly releases list --app <slug>  or  --all');
    }

    final appsToShow = (all || slug == null)
        ? apps
        : apps.where((a) => a['slug'] == slug).toList();
    if (appsToShow.isEmpty) {
      throw CliException('No app with slug: $slug');
    }

    final rows = <Map>[];
    for (final a in appsToShow) {
      final rels = (await api.get('/api/v1/apps/${a['id']}/releases') as Map)['releases'] as List;
      for (final r in rels) {
        rows.add({
          'app': a['slug'],
          ...r,
        });
      }
    }

    if (asJson) {
      print(const JsonEncoder.withIndent('  ')
          .convert({'count': rows.length, 'releases': rows}));
      return;
    }

    if (rows.isEmpty) {
      print('No releases yet.');
      print('Create one: patchfly releases create --app <slug> --version 1.0.0+1');
      return;
    }

    print('${'APP'.padRight(40)} ${'VERSION'.padRight(16)} ${'CHANNEL'.padRight(10)} ${'ACTIVE'.padRight(7)} ${'PATCHES'.padRight(8)} ID');
    for (final r in rows) {
      print(
        '${r['app'].toString().padRight(40)} ${r['version'].toString().padRight(16)} ${r['channelName'].toString().padRight(10)} ${(r['isActive'] ? 'yes' : 'no').padRight(7)} ${r['patchCount'].toString().padRight(8)} ${r['id']}',
      );
    }
  }

  Future<void> _create(ApiClient api, ArgResults args, bool asJson) async {
    final slug = args['app'] as String?;
    final version = args['version'] as String?;
    if (slug == null || version == null) {
      throw CliException('--app and --version are required',
          hint: 'patchfly releases create --app <slug> --version 1.0.0+1');
    }

    final apps = (await api.get('/api/v1/apps') as Map)['apps'] as List;
    final app = apps.firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) throw CliException('No app with slug: $slug');

    final res = await api.post('/api/v1/apps/${app['id']}/releases', {
      'version': version,
      'channel': args['channel'] ?? 'stable',
      'notes': args['notes'],
    });
    final rel = (res as Map)['release'] as Map;

    if (asJson) {
      print(const JsonEncoder.withIndent('  ').convert(rel));
      return;
    }

    print('✓ Created release ${rel['version']} on ${rel['channelName']}');
    print('  ID:      ${rel['id']}');
    print('  App:     ${app['slug']}');
    if (rel['notes'] != null) print('  Notes:   ${rel['notes']}');
  }
}
