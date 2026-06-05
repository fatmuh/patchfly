// `patchfly whoami` — show current logged-in user.

import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class WhoamiCommand implements CommandRunner {
  @override
  String get name => 'whoami';
  @override
  String get description => 'Show the current logged-in user';

  @override
  Future<void> run(List<String> args) async {
    if (args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return;
    }
    final cfg = await ConfigStore.load();
    if (cfg.token == null && cfg.apiKey == null) {
      throw CliException('Not logged in. Run `patchfly login` first.');
    }
    final api = ApiClient(
      baseUrl: ConfigStore.resolveServer(cfg),
      authHeader: () => cfg.authHeader,
    );
    final apps = await api.get('/api/v1/apps');
    final list = (apps as Map)['apps'] as List;
    print('Server:  ${ConfigStore.resolveServer(cfg)}');
    print('Email:   ${cfg.userEmail ?? "(unknown)"}');
    print('Auth:    ${cfg.apiKey != null ? "API key" : "JWT"}');
    print('Apps:    ${list.length}');
    for (final a in list) {
      print('  - ${a['slug']} (${a['id']})');
    }
  }

  void _printUsage() {
    print('''
patchfly whoami — show the current logged-in user

Usage:
  patchfly whoami

Output:
  Server:  the server URL you're talking to
  Email:   your login email
  Auth:    JWT (email/password) or API key
  Apps:    list of apps you own (slug + id)

Examples:
  patchfly whoami
''');
  }
}
