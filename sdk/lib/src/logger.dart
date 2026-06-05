// Minimal logger so SDK output is consistent and easy to filter.

import 'package:logging/logging.dart';

class PatchflyLogger {
  static final Logger _log = Logger('patchfly');

  static void setup({Level level = Level.INFO}) {
    // The `logging` package requires hierarchicalLoggingEnabled = true
    // to set the level on a non-root Logger. Without this it throws
    // 'Unsupported operation: Please set hierarchicalLoggingEnabled to true'.
    hierarchicalLoggingEnabled = true;
    Logger.root.level = level;
    _log.level = level;
    Logger.root.onRecord.listen((rec) {
      if (rec.loggerName != 'patchfly') return;
      // ignore: avoid_print
      print('[patchfly] ${rec.level.name}: ${rec.message}');
    });
  }

  static void info(String msg) => _log.info(msg);
  static void warn(String msg) => _log.warning(msg);
  static void error(String msg, [Object? err, StackTrace? st]) =>
      _log.severe(msg, err, st);
  static void debug(String msg) => _log.fine(msg);
}
