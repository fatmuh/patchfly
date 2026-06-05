// `patchfly register` — create a new user account.

import 'dart:io';
import 'package:args/args.dart';
import '../api_client.dart';
import '../cli.dart';
import '../config.dart';

class RegisterCommand implements CommandRunner {
  @override
  String get name => 'register';
  @override
  String get description => 'Register a new Patchfly account';

  @override
  Future<void> run(List<String> args) async {
    final parser = ArgParser()
      ..addOption('email', abbr: 'e')
      ..addOption('password', abbr: 'p')
      ..addOption('name', abbr: 'n')
      ..addOption('server', abbr: 's');
    final result = parser.parse(args);

    final cfg = await ConfigStore.load();
    final server = (result['server'] as String?) ??
        ConfigStore.resolveServer(cfg);

    var email = result['email'] as String?;
    var password = result['password'] as String?;
    var name = result['name'] as String?;

    if (email == null) {
      stdout.write('Email: ');
      email = stdin.readLineSync()?.trim();
    }
    if (password == null) {
      stdout.write('Password (min 8 chars): ');
      stdin.echoMode = false;
      password = stdin.readLineSync()?.trim();
      stdin.echoMode = true;
      stdout.writeln('');
    }
    if (name == null) {
      stdout.write('Name (optional): ');
      name = stdin.readLineSync()?.trim();
    }

    if (email == null || email.isEmpty) {
      throw CliException('Email is required');
    }
    if (password == null || password.length < 8) {
      throw CliException('Password must be at least 8 characters');
    }

    final api = ApiClient(baseUrl: server, authHeader: () => '');
    final res = await api.post('/api/v1/auth/register', {
      'email': email,
      'password': password,
      'name': name,
    });
    final token = (res as Map)['token'] as String;
    final user = res['user'] as Map;
    final newCfg = cfg.copyWith(
      server: server,
      token: token,
      userEmail: user['email'] as String?,
    );
    await ConfigStore.save(newCfg);
    print('✓ Registered and logged in as ${user['email']}');
  }
}
