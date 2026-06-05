// Barrel for models + parsing helpers.

import '../db/database.dart' show Row;

export '../db/database.dart' show Row;
export 'api_key.dart';
export 'app.dart';
export 'patch.dart';
export 'release.dart';
export 'user.dart';

T? firstRow<T>(List<Row> rows, T Function(Row) parser) {
  if (rows.isEmpty) return null;
  return parser(rows.first);
}

List<T> allRows<T>(List<Row> rows, T Function(Row) parser) {
  return rows.map(parser).toList();
}
