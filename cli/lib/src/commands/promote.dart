// `patchfly promote` — DEPRECATED alias for `patches promote`.
//
// The old top-level `promote` command has been replaced by
// `patches promote <number> --app <slug>`, which has a saner
// CLI (no manual release ID, takes the patch number directly).
// This shim forwards old invocations to the new command.

import '../cli.dart';
import 'patches.dart';

class PromoteCommand implements CommandRunner {
  @override
  String get name => 'promote';
  @override
  String get description =>
      'Activate a patch (DEPRECATED — use: patches promote <number> --app <slug>)';

  @override
  Future<void> run(List<String> args) async {
    print('Note: `patchfly promote` is deprecated. Use `patchfly patches promote` instead.');
    print('');
    // Forward to the new command. The new `patches promote` parser expects
    // positional <number> and --app <slug>. Try to be helpful by mapping the
    // old --patch <num> to positional when present.
    final forwarded = <String>[];
    var i = 0;
    while (i < args.length) {
      final a = args[i];
      if (a == '--patch' && i + 1 < args.length) {
        forwarded.add(args[i + 1]);
        i += 2;
      } else {
        forwarded.add(a);
        i += 1;
      }
    }
    print('Running: patchfly patches ${forwarded.join(' ')}');
    print('');
    await PatchesCommand().run(['promote', ...forwarded]);
  }
}
