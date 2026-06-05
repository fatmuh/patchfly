// Patchfly server entrypoint.
//
// Run: dart run bin/server.dart
// Or built binary: ./bin/server

import 'package:patchfly_server/main.dart';

Future<void> main(List<String> args) async {
  await bootstrap(args: args);
}
