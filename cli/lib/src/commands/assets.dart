// cli/lib/src/commands/assets.dart
//
// Patchfly CLI — asset/config upload command.

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
    if (args.isEmpty) {
      _printUsage();
      return;
    }
    final sub = args.first;
    final subArgs = args.sublist(1);
    switch (sub) {
      case 'push':
        await _PushCommand().run(subArgs);
        break;
      case 'list':
        await _ListCommand().run(subArgs);
        break;
      default:
        print('Unknown subcommand: $sub');
        _printUsage();
    }
  }

  void _printUsage() {
    print('Usage: patchfly assets <push|list> ...');
    print('  push <appId> <zipPath> [--changelog "..."]');
    print('  list <appId>');
  }
}

class _PushCommand implements CommandRunner {
  @override
  String get name => 'push';
  @override
  String get description => 'Upload a new asset bundle (zip file)';

  @override
  Future<void> run(List<String> args) async {
    if (args.length != 2) {
      stderr.writeln('Usage: patchfly assets push <appId> <zipPath>');
      return;
    }
    final appId = args[0];
    final zipPath = args[1];
    final file = File(zipPath);
    if (!file.existsSync()) {
      stderr.writeln('File not found: $zipPath');
      return;
    }
    final bytes = file.readAsBytesSync();
    final sha = sha256.convert(bytes).toString();
    final config = await ConfigStore.load();
    final token = config.token;
    if (token == null) {
      stderr.writeln('Not logged in. Run: patchfly login');
      return;
    }
    final server = config.server;
    if (server == null) {
      stderr.writeln('No server configured. Run: patchfly init');
      return;
    }
    final url = '$server/api/v1/apps/$appId/assets';
    final r = await http.post(
      Uri.parse(url),
      headers: {
        'authorization': 'Bearer $token',
        'x-patchfly-asset-sha256': sha,
        'content-type': 'application/zip',
      },
      body: bytes,
    );
    if (r.statusCode != 200) {
      stderr.writeln('Upload failed: ${r.statusCode} ${r.body}');
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
    if (args.length != 1) {
      stderr.writeln('Usage: patchfly assets list <appId>');
      return;
    }
    final appId = args[0];
    final config = await ConfigStore.load();
    final token = config.token;
    if (token == null) {
      stderr.writeln('Not logged in.');
      return;
    }
    final r = await http.get(
      Uri.parse('${config.server}/api/v1/apps/$appId'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (r.statusCode != 200) {
      stderr.writeln('Failed: ${r.statusCode}');
      return;
    }
    print(r.body);
  }
}
