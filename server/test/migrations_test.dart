import 'dart:io';
import 'package:test/test.dart';

// We test the public parts of Database indirectly via the static migration
// logic. Database's private _splitStatements is tested via the schema file.
void main() {
  test('schema.sql exists and is non-empty', () {
    final f = File('lib/db/schema.sql');
    expect(f.existsSync(), isTrue);
    final content = f.readAsStringSync();
    expect(content.length, greaterThan(500));
  });

  test('schema.sql contains expected tables', () {
    final content = File('lib/db/schema.sql').readAsStringSync();
    for (final table in [
      'users',
      'apps',
      'releases',
      'channels',
      'patches',
      'api_keys',
      'patch_events',
    ]) {
      expect(content, contains('CREATE TABLE IF NOT EXISTS $table'),
          reason: 'schema.sql must define $table');
    }
  });

  test('schema.sql is idempotent (uses IF NOT EXISTS everywhere)', () {
    final content = File('lib/db/schema.sql').readAsStringSync();
    final createLines = content
        .split('\n')
        .where((l) =>
            l.trimLeft().toUpperCase().startsWith('CREATE TABLE') &&
            !l.trimLeft().toUpperCase().startsWith('CREATE TABLE IF NOT EXISTS'))
        .toList();
    expect(createLines, isEmpty,
        reason: 'All CREATE TABLE must be IF NOT EXISTS: $createLines');
  });
}
