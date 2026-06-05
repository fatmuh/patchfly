// `patchfly patches` — list, inspect, and promote patches.

import 'dart:convert';
import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class PatchesCommand implements CommandRunner {
  @override
  String get name => 'patches';
  @override
  String get description => 'List, inspect, or promote patches';

  @override
  Future<void> run(List<String> args) async {
    if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
      _printUsage();
      return;
    }

    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('json', help: 'Output as JSON (for piping into jq etc.)')
      ..addCommand('list', _listParser())
      ..addCommand('get', _getParser())
      ..addCommand('promote', _promoteParser());

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

    try {
      if (sub == null || sub == 'list') {
        await _list(api, result.command!, asJson);
      } else if (sub == 'get') {
        final rest = result.command!.rest;
        if (rest.isEmpty) {
          throw CliException('Usage: patchfly patches get <patch-id>',
              hint: 'Get a patch ID from `patchfly patches list`');
        }
        await _get(api, rest.first, asJson);
      } else if (sub == 'promote') {
        await _promote(api, result.command!, asJson);
      } else {
        _printUsage();
      }
    } on ApiException catch (e) {
      throw CliException('Server error: ${e.message}',
          hint: 'Verify auth with `patchfly whoami`');
    }
  }

  static ArgParser _listParser() => ArgParser()
    ..addOption('app', abbr: 'a', help: 'App slug (required), e.g. com.example.test')
    ..addOption('release',
        help: 'Release ID (default: latest active release for the app)');

  static ArgParser _getParser() => ArgParser();

  static ArgParser _promoteParser() => ArgParser()
    ..addOption('app', abbr: 'a', help: 'App slug (required)');

  void _printUsage() {
    print('''
patchfly patches — list, inspect, and promote patches for an app

Usage:
  patchfly patches <subcommand> [options]

Subcommands:
  list [options]      List all patches for an app
  get <id>            Show details of a single patch (by UUID)
  promote <number>    Activate a patch by its number (sets rollout to 100%)

Common options:
  --json              Output as JSON (for piping into jq etc.)
  -h, --help          Show this help

Options for `list`:
  -a, --app <slug>    App slug (required)
      --release <id>  Release ID (default: latest active release)

Options for `promote`:
  -a, --app <slug>    App slug (required)

Examples:
  # List all patches for an app
  patchfly patches list --app com.example.test

  # Show full details of a specific patch
  patchfly patches get b5a89965-f833-4e09-a4ce-7d87f3251992

  # Activate patch #2 (sets rollout to 100% so all matching devices receive it)
  patchfly patches promote 2 --app com.example.test

  # JSON output for piping
  patchfly patches list --app com.example.test --json

  # Get ID of latest patch via jq
  patchfly patches list --app com.example.test --json | jq -r '.patches[-1].id'

  # Use that ID to promote the latest patch
  patchfly patches promote \$(patchfly patches list --app com.example.test --json | jq '.patches | length') --app com.example.test
''');
  }

  // ----- helpers -----------------------------------------------------------

  Future<String> _resolveAppId(ApiClient api, String slug) async {
    final apps = (await api.get('/api/v1/apps') as Map)['apps'] as List;
    final app = apps.firstWhere((a) => a['slug'] == slug, orElse: () => null);
    if (app == null) {
      throw CliException('No app with slug: $slug',
          hint: 'patchfly apps create --slug $slug --name "..."');
    }
    return app['id'] as String;
  }

  Future<String> _resolveReleaseId(
      ApiClient api, String appId, String? override) async {
    if (override != null && override.isNotEmpty) return override;
    final rels = (await api.get('/api/v1/apps/$appId/releases') as Map)['releases'] as List;
    if (rels.isEmpty) {
      throw CliException('App has no releases yet',
          hint: 'patchfly releases create --app <slug> --version 1.0.0+1');
    }
    final active = rels.firstWhere((r) => r['isActive'] == true, orElse: () => null);
    if (active == null) {
      throw CliException('App has no active release',
          hint: 'Activate a release in the dashboard, or create one with `patchfly releases create`');
    }
    return active['id'] as String;
  }

  Future<List<Map>> _listPatches(ApiClient api, String releaseId) async {
    final res = await api.get('/api/v1/releases/$releaseId/patches') as Map;
    return (res['patches'] as List).cast<Map>();
  }

  // ----- subcommands -------------------------------------------------------

  Future<void> _list(ApiClient api, ArgResults args, bool asJson) async {
    final slug = args['app'] as String?;
    if (slug == null) {
      throw CliException('--app is required',
          hint: 'patchfly patches list --app <slug>');
    }

    final appId = await _resolveAppId(api, slug);
    final releaseId =
        await _resolveReleaseId(api, appId, args['release'] as String?);
    final patches = await _listPatches(api, releaseId);

    if (asJson) {
      final out = {
        'app': slug,
        'appId': appId,
        'releaseId': releaseId,
        'count': patches.length,
        'patches': patches,
      };
      print(const JsonEncoder.withIndent('  ').convert(out));
      return;
    }

    if (patches.isEmpty) {
      print('No patches yet for app "$slug".');
      print('');
      print('Build & upload a patch:');
      print('  patchfly patch --app $slug');
      print('');
      print('Or with explicit config:');
      print('  patchfly patch --config ./patchfly.yaml --app $slug');
      return;
    }

    print('App:      $slug');
    print('Release:  $releaseId');
    print('Patches:  ${patches.length}');
    print('');
    print('${'#'.padRight(4)} ${'SHA-256 (16)'.padRight(18)} ${'SIZE'.padRight(10)} ${'ROLLOUT'.padRight(8)} ${'DELTA'.padRight(5)} CREATED              ID');
    for (final p in patches) {
      final num = p['patchNumber'].toString().padRight(4);
      final sha = p['sha256'].toString().substring(0, 16).padRight(18);
      final size = _formatBytes(p['sizeBytes'] as int).padRight(10);
      final rollout = ('${p['rolloutPercent']}%').padRight(8);
      final delta = (p['isDelta'] == true ? 'yes' : 'no').padRight(5);
      final created = (p['createdAt'] as String).substring(0, 19);
      print('$num $sha $size $rollout $delta $created  ${p['id']}');
    }
  }

  Future<void> _get(ApiClient api, String id, bool asJson) async {
    final res = await api.get('/api/v1/patches/$id') as Map;
    final p = res['patch'] as Map;

    if (asJson) {
      print(const JsonEncoder.withIndent('  ').convert(p));
      return;
    }

    print('Patch #${p['patchNumber']}');
    print('  ID:           ${p['id']}');
    print('  SHA-256:      ${p['sha256']}');
    print('  Signature:    ${p['signature']}');
    print('  Size:         ${_formatBytes(p['sizeBytes'] as int)} (${p['sizeBytes']} bytes)');
    print('  Is delta:     ${p['isDelta']}');
    if (p['basePatchId'] != null) {
      print('  Base patch:   ${p['basePatchId']}');
    }
    if (p['minAppVersion'] != null) {
      print('  Min app ver:  ${p['minAppVersion']}');
    }
    if (p['maxAppVersion'] != null) {
      print('  Max app ver:  ${p['maxAppVersion']}');
    }
    print('  Rollout:      ${p['rolloutPercent']}%');
    print('  Download URL: ${p['downloadUrl']}');
    print('  Created:      ${p['createdAt']}');
  }

  Future<void> _promote(ApiClient api, ArgResults args, bool asJson) async {
    if (args.rest.isEmpty) {
      throw CliException('Usage: patchfly patches promote <number> --app <slug>');
    }
    final patchNum = int.tryParse(args.rest.first);
    if (patchNum == null) {
      throw CliException('Patch number must be a positive integer, got: "${args.rest.first}"',
          hint: 'Run `patchfly patches list --app <slug>` to see available patch numbers');
    }
    final slug = args['app'] as String?;
    if (slug == null) {
      throw CliException('--app is required',
          hint: 'patchfly patches promote <number> --app <slug>');
    }

    final appId = await _resolveAppId(api, slug);
    final releaseId = await _resolveReleaseId(api, appId, null);
    final patches = await _listPatches(api, releaseId);
    Map? patch;
    for (final p in patches) {
      if (p['patchNumber'] == patchNum) {
        patch = p;
        break;
      }
    }
    if (patch == null) {
      throw CliException('No patch #$patchNum on release $releaseId',
          hint: 'Run `patchfly patches list --app $slug` to see available patches');
    }

    final res = await api.post('/api/v1/patches/${patch['id']}/activate') as Map;
    final updated = (res['patch'] ?? res) as Map;

    if (asJson) {
      print(const JsonEncoder.withIndent('  ').convert(updated));
      return;
    }

    print('✓ Patch #$patchNum is now ACTIVE (100% rollout)');
    print('  ID:       ${updated['id'] ?? patch['id']}');
    print('  Rollout:  ${updated['rolloutPercent'] ?? 100}%');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
