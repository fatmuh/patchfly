// Event service — analytics / audit log of SDK actions.

import 'dart:convert';
import '../db/database.dart';

class EventService {
  final Database _db;
  EventService(this._db);

  Future<void> record({
    String? patchId,
    required String appId,
    required String eventType,
    String? appVersion,
    String? deviceId,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) async {
    await _db.execute(
      '''INSERT INTO patch_events
           (patch_id, app_id, event_type, app_version, device_id, error_message, metadata)
         VALUES (@p, @a, @t, @v, @d, @e, @m)''',
      {
        'p': patchId,
        'a': appId,
        't': eventType,
        'v': appVersion,
        'd': deviceId,
        'e': errorMessage,
        'm': metadata != null ? jsonEncode(metadata) : null,
      },
    );
  }

  Future<List<Map<String, dynamic>>> summary(String appId,
      {Duration window = const Duration(days: 30)}) async {
    final since = DateTime.now().toUtc().subtract(window);
    final rows = await _db.query(
      '''SELECT event_type, COUNT(*) AS n
         FROM patch_events
         WHERE app_id = @a AND created_at >= @s
         GROUP BY event_type''',
      {'a': appId, 's': since.toIso8601String()},
    );
    return rows
        .map((r) => {
              'eventType': r.col<String>('event_type'),
              'count': r.col<int>('n'),
            })
        .toList();
  }
}
