// Patchfly CLI entrypoint.

import 'package:patchfly/src/cli.dart';

Future<void> main(List<String> args) async {
  await runCli(args);
}
