// API key service — used by CLI for authentication.

import 'dart:async';
import '../db/database.dart';
import '../models/api_key.dart';
import '../models/models.dart' show firstRow, allRows;
import '../utils/hash.dart';
import '../utils/json.dart';
import '../utils/jwt.dart' show AuthException;

export '../utils/jwt.dart' show AuthException;

class ApiKeyService {
  static const String keyPrefixLiteral = 'pft_';

  final Database _db;
  ApiKeyService(this._db);

  Future<({String plaintext, ApiKey record})> create({
    required String userId,
    required String name,
    Duration? expiresIn,
  }) async {
    final plaintext = '$keyPrefixLiteral${randomToken(bytes: 32)}';
    final hash = sha256Hex(plaintext);
    final prefix = tokenPrefix(plaintext);

    final rows = await _db.query(
      '''INSERT INTO api_keys (user_id, name, key_hash, key_prefix, expires_at)
         VALUES (@u, @n, @h, @p, @e)
         RETURNING *''',
      {
        'u': userId,
        'n': name,
        'h': hash,
        'p': prefix,
        'e': expiresIn != null
            ? DateTime.now().toUtc().add(expiresIn)
            : null,
      },
    );

    return (plaintext: plaintext, record: firstRow(rows, ApiKey.fromRow)!);
  }

  Future<({ApiKey key, String userId})> verify(String plaintext) async {
    if (!plaintext.startsWith(keyPrefixLiteral)) {
      throw AuthException('Invalid API key');
    }
    final hash = sha256Hex(plaintext);

    final rows = await _db.query(
      'SELECT * FROM api_keys WHERE key_hash = @h',
      {'h': hash},
    );
    if (rows.isEmpty) throw AuthException('Invalid API key');

    final key = firstRow(rows, ApiKey.fromRow)!;
    if (key.expiresAt != null && key.expiresAt!.isBefore(DateTime.now())) {
      throw AuthException('API key expired');
    }

    unawaited(
      _db.execute(
        'UPDATE api_keys SET last_used_at = NOW() WHERE id = @i',
        {'i': key.id},
      ),
    );

    return (key: key, userId: key.userId);
  }

  Future<List<ApiKey>> listForUser(String userId) async {
    final rows = await _db.query(
      '''SELECT * FROM api_keys
         WHERE user_id = @u
         ORDER BY created_at DESC''',
      {'u': userId},
    );
    return allRows(rows, ApiKey.fromRow);
  }

  Future<void> revoke(String userId, String keyId) async {
    final affected = await _db.execute(
      'DELETE FROM api_keys WHERE id = @i AND user_id = @u',
      {'i': keyId, 'u': userId},
    );
    if (affected == 0) throw NotFound('API key not found');
  }
}
