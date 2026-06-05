// `patchfly assets` — manage asset/config bundles for an app.
//
// (Note: most users will use `patchfly patch` for code patches, and
// `patchfly assets push` only for asset/config bundles that ship
// outside a Flutter AOT build.)

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../cli.dart';

class AssetsCommand implements CommandRunner {
  @override
  String get name => 'assets';
  @override
  String get description => 'Manage asset/config bundles for an app';

  @override
  Future<void> run(List<String> args) async {
    if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
      _printUsage();
      return;
    }
    final sub = args.first;
    final subArgs = args.sublist(1);
    try {
      switch (sub) {
        case 'push':
          await _PushCommand().run(subArgs);
          break;
        case 'list':
          await _ListCommand().run(subArgs);
          break;
        case '--help':
        case '-h':
          _printUsage();
          break;
        default:
          print('Unknown subcommand: $sub');
          _printUsage();
      }
    } on CliException catch (e) {
      print('Error: ${e.message}');
      if (e.hint != null) print('Hint: ${e.hint}');
    }
  }

  void _printUsage() {
    print('''
patchfly assets — manage asset/config bundles for an app

Usage:
  patchfly assets <subcommand> [options]

Subcommands:
  push <appId> <zipPath>     Upload a new asset bundle (zip file)
  list <appId>               List asset versions for an app

Options for `push`:
      --changelog "..."       Changelog text for this asset version

Examples:
  # Upload an asset bundle (zip)
  patchfly assets push fb18aece-5dfc-4865-9435-77200efa3f17 ./bundle.zip

  # With a changelog
  patchfly assets push <appId> ./bundle.zip --changelog "New splash screen"

  # List versions
  patchfly assets list <appId>
''');
  }
}

class _PushCommand implements CommandRunner {
  @override
  String get name => 'push';
  @override
  String get description => 'Upload a new asset bundle (zip file)';

  @override
  Future<void> run(List<String> args) async {
    // Parse: <appId> <zipPath> [--changelog "..."]
    var changelog = '""';
    final positional = <String>[];
    var i = 0;
    while (i < args.length) {
      if (args[i] == '--changelog' && i + 1 < args.length) {
        changelog = args[i + 1];
        i += 2;
      } else if (args[i] == '--help' || args[i] == '-h') {
        print('Usage: patchfly assets push <appId> <zipPath> [--changelog "..."]');
        return;
      } else {
        positional.add(args[i]);
        i += 1;
      }
    }
    if (positional.length != 2) {
      print('Usage: patchfly assets push <appId> <zipPath> [--changelog "..."]');
      return;
    }
    final appId = positional[0];
    final zipPath = positional[1];
    final file = File(zipPath);
    if (!file.existsSync()) {
      print('Error: File not found: $zipPath');
      return;
    }
    final bytes = file.readAsBytesSync();
    final sha = sha256.convert(bytes).toString();
    final config = await ConfigStore.load();
    final token = config.token;
    if (token == null) {
      print('Error: Not logged in. Run: patchfly login');
      return;
    }
    final server = config.server;
    if (server == null) {
      print('Error: No server configured. Run: patchfly init');
      return;
    }
    final url = '$server/api/v1/apps/$appId/assets';
    final r = await http.post(
      Uri.parse(url),
      headers: {
        'authorization': 'Bearer $token',
        'x-patchfly-asset-sha256': sha,
        'content-type': 'application/zip',
        'x-patchfly-changelog': changelog,
      },
      body: bytes,
    );
    if (r.statusCode != 200) {
      print('Error: Upload failed: ${r.statusCode} ${r.body}');
      return;
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    print('✓ Asset pushed');
    print('  Version:  ${data['version']}');
    print('  Size:     ${data['sizeBytes']} bytes');
    print('  SHA-256:  ${data['sha256']}');
  }
}

class _ListCommand implements CommandRunner {
  @override
  String get name => 'list';
  @override
  String get description => 'List asset versions for an app';

  @override
  Future<void> run(List<String> args) async {
    if (args.contains('--help') || args.contains('-h')) {
      print('Usage: patchfly assets list <appId>');
      return;
    }
    if (args.length != 1) {
      print('Usage: patchfly assets list <appId>');
      return;
    }
    final appId = args[0];
    final config = await ConfigStore.load();
    final token = config.token;
    if (token == null) {
      print('Error: Not logged in.');
      return;
    }
    final r = await http.get(
      Uri.parse('${config.server}/api/v1/apps/$appId'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (r.statusCode != 200) {
      print('Error: ${r.statusCode}');
      return;
    }
    print(r.body);
  }
}
