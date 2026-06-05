// `patchfly apps` — manage apps.

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
      ..addCommand('list')
      ..addCommand('create')
      ..addCommand('get')
      ..addCommand('delete');
    final result = parser.parse(args);

    final cfg = await ConfigStore.load();
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );

    final cmd = result.command?.name;
    if (cmd == null || cmd == 'list') {
      await _list(api);
    } else if (cmd == 'create') {
      await _create(api, result.command!);
    } else if (cmd == 'get') {
      await _get(api, result.command!);
    } else if (cmd == 'delete') {
      await _delete(api, result.command!);
    } else {
      print('Usage: patchfly apps <list|create|get|delete>');
    }
  }

  Future<void> _list(ApiClient api) async {
    final res = await api.get('/api/v1/apps');
    final apps = (res as Map)['apps'] as List;
    if (apps.isEmpty) {
      print('No apps. Run `patchfly apps create --slug com.your.app --name "Your App"`.');
      return;
    }
    print('${'SLUG'.padRight(40)} ${'NAME'.padRight(30)} ${'PLATFORM'.padRight(10)} ${'SDK KEY'.padRight(15)} ID');
    for (final a in apps) {
      print('${a['slug'].toString().padRight(40)} ${a['name'].toString().padRight(30)} ${a['platform'].toString().padRight(10)} ${a['sdkKeyPrefix'].toString().padRight(15)} ${a['id']}');
    }
  }

  Future<void> _create(ApiClient api, ArgResults args) async {
    final p = ArgParser()
      ..addOption('slug', help: 'Reverse-DNS slug, e.g. com.acme.myapp')
      ..addOption('name', help: 'Display name')
      ..addOption('platform',
          allowed: ['android', 'ios', 'all'], defaultsTo: 'android');
    final r = p.parse(args.rest);
    final slug = r['slug'] as String?;
    final name = r['name'] as String?;
    if (slug == null || name == null) {
      throw CliException('--slug and --name are required');
    }
    final res = await api.post('/api/v1/apps', {
      'slug': slug,
      'name': name,
      'platform': r['platform'],
    });
    final app = (res as Map)['app'] as Map;
    final sdkKey = res['sdkKey'] as String;
    print('✓ App created: ${app['slug']} (${app['id']})');
    print('');
    print('SDK key (save now, you cannot see it again):');
    print('  $sdkKey');
  }

  Future<void> _get(ApiClient api, ArgResults args) async {
    if (args.rest.isEmpty) {
      throw CliException('Usage: patchfly apps get <slug>');
    }
    final slug = args.rest.first;
    final list = await api.get('/api/v1/apps') as Map;
    final apps = list['apps'] as List;
    final app = apps.firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) throw CliException('No app with slug: $slug');
    print('ID:        ${app['id']}');
    print('Slug:      ${app['slug']}');
    print('Name:      ${app['name']}');
    print('Platform:  ${app['platform']}');
    print('SDK key:   ${app['sdkKeyPrefix']}...');
  }

  Future<void> _delete(ApiClient api, ArgResults args) async {
    if (args.rest.isEmpty) {
      throw CliException('Usage: patchfly apps delete <slug>');
    }
    final slug = args.rest.first;
    final list = await api.get('/api/v1/apps') as Map;
    final apps = list['apps'] as List;
    final app = apps.firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) throw CliException('No app with slug: $slug');
    await api.delete('/api/v1/apps/${app['id']}');
    print('✓ Deleted app $slug');
  }
}
