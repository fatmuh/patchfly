// Channel service.

import '../db/database.dart';
import '../models/release.dart';
import '../models/models.dart' show firstRow, allRows;

class ChannelService {
  final Database _db;
  ChannelService(this._db);

  Future<List<Channel>> listForApp(String appId) async {
    final rows = await _db.query(
      'SELECT * FROM channels WHERE app_id = @a ORDER BY name',
      {'a': appId},
    );
    return allRows(rows, Channel.fromRow);
  }

  Future<Channel> ensureChannel({
    required String appId,
    required String name,
  }) async {
    final rows = await _db.query(
      '''INSERT INTO channels (app_id, name) VALUES (@a, @n)
         ON CONFLICT (app_id, name) DO UPDATE SET name = EXCLUDED.name
         RETURNING *''',
      {'a': appId, 'n': name},
    );
    return firstRow(rows, Channel.fromRow)!;
  }
}
