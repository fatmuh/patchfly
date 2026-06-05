// `patchfly releases` — manage releases.

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
      ..addCommand('list', _emptySubParser())
      ..addCommand('create', _createSubParser());
    final result = parser.parse(args);

    final cfg = await ConfigStore.load();
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );

    final cmd = result.command?.name;
    if (cmd == null || cmd == 'list') {
      await _list(api, result.rest);
    } else if (cmd == 'create') {
      await _create(api, result.command!);
    }
  }

  static ArgParser _emptySubParser() => ArgParser();

  static ArgParser _createSubParser() => ArgParser()
    ..addOption('app', help: 'App slug')
    ..addOption('version', help: 'Version string, e.g. 1.4.2+15')
    ..addOption('channel',
        allowed: ['stable', 'beta', 'internal', 'alpha'],
        defaultsTo: 'stable')
    ..addOption('notes', help: 'Release notes');

  Future<void> _list(ApiClient api, List<String> rest) async {
    if (rest.isEmpty) {
      throw CliException('Usage: patchfly releases list <app-slug>');
    }
    final slug = rest.first;
    final apps = await api.get('/api/v1/apps') as Map;
    final app = (apps['apps'] as List)
        .firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) throw CliException('No app with slug: $slug');

    final res = await api.get('/api/v1/apps/${app['id']}/releases') as Map;
    final rels = res['releases'] as List;
    if (rels.isEmpty) {
      print('No releases yet. Create one with: patchfly releases create $slug --version 1.0.0');
      return;
    }
    print('${'VERSION'.padRight(20)} ${'CHANNEL'.padRight(10)} ${'ACTIVE'.padRight(8)} ${'PATCHES'.padRight(8)} ID');
    for (final r in rels) {
      print(
        '${r['version'].toString().padRight(20)} ${r['channelName'].toString().padRight(10)} ${(r['isActive'] ? '✓' : '').padRight(8)} ${r['patchCount'].toString().padRight(8)} ${r['id']}',
      );
    }
  }

  Future<void> _create(ApiClient api, ArgResults args) async {
    final slug = args['app'] as String?;
    final version = args['version'] as String?;
    if (slug == null || version == null) {
      throw CliException('--app and --version are required');
    }

    final apps = await api.get('/api/v1/apps') as Map;
    final app = (apps['apps'] as List)
        .firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) throw CliException('No app with slug: $slug');

    final res = await api.post('/api/v1/apps/${app['id']}/releases', {
      'version': version,
      'channel': args['channel'] ?? 'stable',
      'notes': args['notes'],
    });
    final rel = (res as Map)['release'] as Map;
    print('✓ Created release ${rel['version']} on ${rel['channelName']}');
    print('  ID: ${rel['id']}');
  }
}
