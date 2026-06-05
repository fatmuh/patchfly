// `patchfly login` — authenticate via email/password, or paste an API key.

import 'dart:io';
import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class LoginCommand implements CommandRunner {
  @override
  String get name => 'login';
  @override
  String get description =>
      'Log in to Patchfly (email/password) or paste an API key';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addOption('email', abbr: 'e')
      ..addOption('password', abbr: 'p')
      ..addOption('api-key', help: 'Paste an existing API key (pft_...)')
      ..addOption('server', abbr: 's', help: 'Patchfly server URL');
    final result = parser.parse(args);

    final cfg = await ConfigStore.load();
    final server = (result['server'] as String?) ??
        ConfigStore.resolveServer(cfg);

    // API key path
    if (result['api-key'] != null) {
      final key = result['api-key'] as String;
      final newCfg = cfg.copyWith(apiKey: key, server: server);
      await ConfigStore.save(newCfg);
      print('✓ API key saved. Try `patchfly whoami` to verify.');
      return;
    }

    // Email/password path
    var email = result['email'] as String?;
    var password = result['password'] as String?;

    if (email == null) {
      stdout.write('Email: ');
      email = stdin.readLineSync()?.trim();
    }
    if (password == null) {
      stdout.write('Password: ');
      // Hide input
      stdin.echoMode = false;
      password = stdin.readLineSync()?.trim();
      stdin.echoMode = true;
      stdout.writeln('');
    }
    if (email == null || email.isEmpty) {
      throw CliException('Email is required');
    }
    if (password == null || password.isEmpty) {
      throw CliException('Password is required');
    }

    final api = ApiClient(baseUrl: server, authHeader: () => '');
    try {
      final res = await api.post('/api/v1/auth/login', {
        'email': email,
        'password': password,
      });
      final token = (res as Map)['token'] as String;
      final user = res['user'] as Map;
      final newCfg = cfg.copyWith(
        server: server,
        token: token,
        userEmail: user['email'] as String?,
      );
      await ConfigStore.save(newCfg);
      print('✓ Logged in as ${user['email']}');
    } on ApiException catch (e) {
      if (e.status == 401) {
        throw CliException('Invalid email or password');
      }
      rethrow;
    }
  }
}
