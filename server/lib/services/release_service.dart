// Release service — split out for clean imports.

import '../db/database.dart';
import '../models/release.dart';
import '../models/models.dart' show firstRow, allRows;
import '../utils/json.dart';

class ReleaseService {
  final Database _db;
  ReleaseService(this._db);

  Future<Release> create({
    required String appId,
    required String channelName,
    required String version,
    String? notes,
  }) async {
    final chanRows = await _db.query(
      '''INSERT INTO channels (app_id, name) VALUES (@a, @n)
         ON CONFLICT (app_id, name) DO UPDATE SET name = EXCLUDED.name
         RETURNING id''',
      {'a': appId, 'n': channelName},
    );
    final channelId = chanRows.first.col<String>('id');

    final dup = await _db.queryValue(
      'SELECT id FROM releases WHERE app_id = @a AND version = @v',
      {'a': appId, 'v': version},
    );
    if (dup != null) {
      throw Conflict('Release version $version already exists for this app');
    }

    final activeCount = await _db.queryValue(
      '''SELECT COUNT(*) FROM releases
         WHERE app_id = @a AND channel_id = @c AND is_active = true''',
      {'a': appId, 'c': channelId},
    );

    final rows = await _db.query(
      '''INSERT INTO releases (app_id, channel_id, version, notes, is_active)
         VALUES (@a, @c, @v, @n, @active)
         RETURNING id, app_id, channel_id, version, is_active, notes, created_at''',
      {
        'a': appId,
        'c': channelId,
        'v': version,
        'n': notes,
        'active': activeCount == 0,
      },
    );
    return firstRow(rows, Release.fromRow)!;
  }

  Future<List<Release>> listForApp(String appId) async {
    final rows = await _db.query(
      '''SELECT r.id, r.app_id, r.channel_id, r.version, r.is_active,
                r.notes, r.created_at,
                c.name AS channel_name,
                (SELECT COUNT(*) FROM patches p WHERE p.release_id = r.id)
                  AS patch_count,
                (SELECT patch_number FROM patches p
                 WHERE p.release_id = r.id AND p.is_active = true
                 ORDER BY p.patch_number DESC LIMIT 1) AS active_patch_number
         FROM releases r
         JOIN channels c ON c.id = r.channel_id
         WHERE r.app_id = @a
         ORDER BY r.created_at DESC''',
      {'a': appId},
    );
    return allRows(rows, Release.fromRow);
  }

  Future<Release?> findById(String id) async {
    final rows = await _db.query(
      '''SELECT r.id, r.app_id, r.channel_id, r.version, r.is_active,
                r.notes, r.created_at,
                c.name AS channel_name,
                (SELECT COUNT(*) FROM patches p WHERE p.release_id = r.id)
                  AS patch_count,
                (SELECT patch_number FROM patches p
                 WHERE p.release_id = r.id AND p.is_active = true
                 ORDER BY p.patch_number DESC LIMIT 1) AS active_patch_number
         FROM releases r
         JOIN channels c ON c.id = r.channel_id
         WHERE r.id = @i''',
      {'i': id},
    );
    return firstRow(rows, Release.fromRow);
  }

  Future<Release?> findActiveForChannel({
    required String appId,
    required String channelName,
  }) async {
    final rows = await _db.query(
      '''SELECT r.id, r.app_id, r.channel_id, r.version, r.is_active,
                r.notes, r.created_at,
                c.name AS channel_name
         FROM releases r
         JOIN channels c ON c.id = r.channel_id
         WHERE r.app_id = @a AND c.name = @c AND r.is_active = true
         LIMIT 1''',
      {'a': appId, 'c': channelName},
    );
    return firstRow(rows, Release.fromRow);
  }
}
