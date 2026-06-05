// App model.

import 'models.dart' show Row;

class App {
  final String id;
  final String ownerId;
  final String slug;
  final String name;
  final String platform;
  final String sdkKeyPrefix;
  final DateTime createdAt;
  final DateTime updatedAt;

  App({
    required this.id,
    required this.ownerId,
    required this.slug,
    required this.name,
    required this.platform,
    required this.sdkKeyPrefix,
    required this.createdAt,
    required this.updatedAt,
  });

  factory App.fromRow(Row r) => App(
        id: r.col<String>('id'),
        ownerId: r.col<String>('owner_id'),
        slug: r.col<String>('slug'),
        name: r.col<String>('name'),
        platform: r.col<String>('platform'),
        sdkKeyPrefix: r.col<String>('sdk_key_prefix'),
        createdAt: r.dateTime('created_at'),
        updatedAt: r.dateTime('updated_at'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'platform': platform,
        'sdkKeyPrefix': sdkKeyPrefix,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
