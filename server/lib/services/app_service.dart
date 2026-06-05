// App service — register and manage customer apps.

import '../db/database.dart';
import '../models/app.dart';
import '../models/models.dart' show firstRow, allRows;
import '../utils/hash.dart';
import '../utils/json.dart';

class AppService {
  final Database _db;
  AppService(this._db);

  /// Register a new app. Returns the SDK key plaintext (show once)
  /// and the app record.
  Future<({App app, String sdkKey})> register({
    required String ownerId,
    required String slug,
    required String name,
    String platform = 'android',
  }) async {
    if (!RegExp(r'^[a-z0-9][a-z0-9_]*(\.[a-z0-9_]+)+$').hasMatch(slug)) {
      throw BadRequest('slug must be reverse-DNS, e.g. "com.acme.myapp"');
    }

    final existing = await _db.queryValue(
      'SELECT id FROM apps WHERE slug = @s',
      {'s': slug},
    );
    if (existing != null) {
      throw Conflict('App with this slug already exists');
    }

    final sdkKey = 'pfk_${randomToken(bytes: 32)}';
    final sdkKeyHash = sha256Hex(sdkKey);
    final sdkKeyPrefix = tokenPrefix(sdkKey);

    final rows = await _db.query(
      '''INSERT INTO apps (owner_id, slug, name, platform, sdk_key_hash, sdk_key_prefix)
         VALUES (@o, @s, @n, @p, @h, @x)
         RETURNING *''',
      {
        'o': ownerId,
        's': slug,
        'n': name,
        'p': platform,
        'h': sdkKeyHash,
        'x': sdkKeyPrefix,
      },
    );

    final app = firstRow(rows, App.fromRow)!;

    // Create default channels
    await _db.execute(
      '''INSERT INTO channels (app_id, name) VALUES
         (@a, 'stable'), (@a, 'beta'), (@a, 'internal')
         ON CONFLICT DO NOTHING''',
      {'a': app.id},
    );

    return (app: app, sdkKey: sdkKey);
  }

  /// Rotate the SDK key for an app. Returns the new plaintext key.
  Future<String> rotateSdkKey(String appId, String ownerId) async {
    final newKey = 'pfk_${randomToken(bytes: 32)}';
    final newHash = sha256Hex(newKey);
    final newPrefix = tokenPrefix(newKey);

    final affected = await _db.execute(
      '''UPDATE apps
         SET sdk_key_hash = @h, sdk_key_prefix = @x
         WHERE id = @i AND owner_id = @o''',
      {
        'h': newHash,
        'x': newPrefix,
        'i': appId,
        'o': ownerId,
      },
    );
    if (affected == 0) throw NotFound('App not found');
    return newKey;
  }

  Future<List<App>> listForOwner(String ownerId) async {
    final rows = await _db.query(
      'SELECT * FROM apps WHERE owner_id = @o ORDER BY created_at DESC',
      {'o': ownerId},
    );
    return allRows(rows, App.fromRow);
  }

  Future<App?> findById(String id, {String? ownerId}) async {
    final rows = await _db.query(
      ownerId != null
          ? 'SELECT * FROM apps WHERE id = @i AND owner_id = @o'
          : 'SELECT * FROM apps WHERE id = @i',
      {'i': id, 'o': ownerId},
    );
    return firstRow(rows, App.fromRow);
  }

  /// Used by SDK: authenticate SDK key, return app.
  Future<App?> authenticateSdkKey(String sdkKey) async {
    if (!sdkKey.startsWith('pfk_')) return null;
    final hash = sha256Hex(sdkKey);
    final rows = await _db.query(
      'SELECT * FROM apps WHERE sdk_key_hash = @h',
      {'h': hash},
    );
    return firstRow(rows, App.fromRow);
  }

  Future<void> delete(String id, String ownerId) async {
    final affected = await _db.execute(
      'DELETE FROM apps WHERE id = @i AND owner_id = @o',
      {'i': id, 'o': ownerId},
    );
    if (affected == 0) throw NotFound('App not found');
  }
}
