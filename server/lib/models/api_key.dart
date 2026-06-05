// API key model.

import 'models.dart' show Row;

class ApiKey {
  final String id;
  final String userId;
  final String name;
  final String keyHash;
  final String keyPrefix;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;

  ApiKey({
    required this.id,
    required this.userId,
    required this.name,
    required this.keyHash,
    required this.keyPrefix,
    this.lastUsedAt,
    this.expiresAt,
    required this.createdAt,
  });

  factory ApiKey.fromRow(Row r) => ApiKey(
        id: r.col<String>('id'),
        userId: r.col<String>('user_id'),
        name: r.col<String>('name'),
        keyHash: r.col<String>('key_hash'),
        keyPrefix: r.col<String>('key_prefix'),
        lastUsedAt: r.dateTimeOpt('last_used_at'),
        expiresAt: r.dateTimeOpt('expires_at'),
        createdAt: r.dateTime('created_at'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'keyPrefix': keyPrefix,
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}
