// Top-level CLI dispatcher.

import 'package:args/args.dart';
import 'commands/init.dart';
import 'commands/login.dart';
import 'commands/register.dart';
import 'commands/whoami.dart';
import 'commands/keys.dart';
import 'commands/apps.dart';
import 'commands/assets.dart';
import 'commands/releases.dart';
import 'commands/patch.dart';
import 'commands/patches.dart';
import 'commands/promote.dart';
import 'commands/rollout.dart';
import 'commands/doctor.dart';

const String version = '0.1.0';

Future<void> runCli(List<String> args) async {
  final parser = ArgParser()
    ..addOption('server',
        abbr: 's',
        help: 'Patchfly server URL (default: \$PATCHFLY_SERVER or from config)')
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', abbr: 'v', negatable: false)
    ..addFlag('json', help: 'Output as JSON')
    ..addFlag('verbose', abbr: 'V', help: 'Verbose output');

  final top = parser;

  // Subcommands
  final initCmd = InitCommand();
  final loginCmd = LoginCommand();
  final registerCmd = RegisterCommand();
  final whoamiCmd = WhoamiCommand();
  final keysCmd = KeysCommand();
  final appsCmd = AppsCommand();
  final releasesCmd = ReleasesCommand();
  final patchCmd = PatchCommand();
  final patchesCmd = PatchesCommand();
  final promoteCmd = PromoteCommand(); // legacy: forwards to `patches promote`
  final rolloutCmd = RolloutCommand();
  final doctorCmd = DoctorCommand();
  final assetsCmd = AssetsCommand();

  final commands = <String, CommandRunner>{
    'init': initCmd,
    'login': loginCmd,
    'register': registerCmd,
    'whoami': whoamiCmd,
    'keys': keysCmd,
    'apps': appsCmd,
    'releases': releasesCmd,
    'patch': patchCmd,
    'patches': patchesCmd,
    'promote': promoteCmd, // deprecated, use `patches promote`
    'rollout': rolloutCmd,
    'doctor': doctorCmd,
    'assets': assetsCmd,
  };

  if (args.isEmpty) {
    _printHelp(top, commands);
    return;
  }

  if (args.first == '--help' || args.first == '-h') {
    _printHelp(top, commands);
    return;
  }
  if (args.first == '--version' || args.first == '-v') {
    print('patchfly $version');
    return;
  }

  final commandName = args.first;
  final commandArgs = args.sublist(1);

  final runner = commands[commandName];
  if (runner == null) {
    print('Unknown command: $commandName');
    print('Run "patchfly --help" for usage.');
    return;
  }

  try {
    await runner.run(commandArgs);
  } on CliException catch (e) {
    print('Error: ${e.message}');
    if (e.hint != null) print('Hint: ${e.hint}');
  } catch (e) {
    print('Error: $e');
  }
}

void _printHelp(ArgParser top, Map<String, CommandRunner> commands) {
  print('''
Patchfly CLI v$version
Build & deploy OTA updates to Flutter apps.

Usage:
  patchfly <command> [options]
  patchfly <command> --help      full options for a subcommand

Global options:
${top.usage}

Commands:
''');
  for (final entry in commands.entries) {
    final firstLine = entry.value.description.split('\n').first;
    final tag = entry.key == 'promote' ? ' (deprecated, use: patches promote)' : '';
    print('  ${entry.key.padRight(12)} $firstLine$tag');
  }
  print('''
Common workflows:
  patchfly login                                          log in
  patchfly apps create --slug com.acme.app --name ...     register a new app
  patchfly apps list                                      see apps you own
  patchfly releases create --app ... --version 1.0.0      create a release
  patchfly patch --app ...                                build & upload a patch
  patchfly patches list --app ...                         list patches
  patchfly patches get <id>                               inspect a patch
  patchfly patches promote <number> --app ...             activate a patch

Run `patchfly <command> --help` for full options on any command.
''');
}

/// Interface for a CLI command.
abstract class CommandRunner {
  String get description;
  String get name;
  Future<void> run(List<String> args);
}

class CliException implements Exception {
  final String message;
  final String? hint;
  CliException(this.message, {this.hint});
}
