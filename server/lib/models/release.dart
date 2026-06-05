// Release model.

import 'models.dart' show Row;

class Release {
  final String id;
  final String appId;
  final String channelId;
  final String channelName;
  final String version;
  final bool isActive;
  final String? notes;
  final DateTime createdAt;
  final int patchCount;
  final int? activePatchNumber;

  Release({
    required this.id,
    required this.appId,
    required this.channelId,
    required this.channelName,
    required this.version,
    required this.isActive,
    this.notes,
    required this.createdAt,
    this.patchCount = 0,
    this.activePatchNumber,
  });

  factory Release.fromRow(Row r) => Release(
        id: r.col<String>('id'),
        appId: r.col<String>('app_id'),
        channelId: r.col<String>('channel_id'),
        channelName: r.nullable<String>('channel_name') ?? 'stable',
        version: r.col<String>('version'),
        isActive: r.nullable<bool>('is_active') ?? false,
        notes: r.nullable<String>('notes'),
        createdAt: r.dateTime('created_at'),
        patchCount: r.nullable<int>('patch_count') ?? 0,
        activePatchNumber: r.nullable<int>('active_patch_number'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'appId': appId,
        'channelId': channelId,
        'channelName': channelName,
        'version': version,
        'isActive': isActive,
        'notes': notes,
        'patchCount': patchCount,
        'activePatchNumber': activePatchNumber,
        'createdAt': createdAt.toIso8601String(),
      };
}

class Channel {
  final String id;
  final String appId;
  final String name;
  final DateTime createdAt;

  Channel({
    required this.id,
    required this.appId,
    required this.name,
    required this.createdAt,
  });

  factory Channel.fromRow(Row r) => Channel(
        id: r.col<String>('id'),
        appId: r.col<String>('app_id'),
        name: r.col<String>('name'),
        createdAt: r.dateTime('created_at'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };
}
