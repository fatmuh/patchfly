// Tests for JSON serialization of models.

import 'package:test/test.dart';
import 'package:patchfly_server/models/user.dart';
import 'package:patchfly_server/models/app.dart';
import 'package:patchfly_server/models/patch.dart';
import 'package:patchfly_server/models/release.dart';
import 'package:patchfly_server/db/database.dart' show Row;

Row _row(Map<String, dynamic> m) => Row(m);

void main() {
  group('User.fromRow', () {
    test('parses all fields', () {
      final r = _row({
        'id': 'u1',
        'email': 'a@b.c',
        'name': 'Alice',
        'created_at': '2024-01-01T00:00:00.000Z',
        'password_hash': 'hash',
      });
      final u = User.fromRow(r);
      expect(u.id, 'u1');
      expect(u.email, 'a@b.c');
      expect(u.name, 'Alice');
      expect(u.passwordHash, 'hash');
    });

    test('toJson omits password_hash', () {
      final u = User(
        id: 'u1',
        email: 'a@b.c',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );
      final j = u.toJson();
      expect(j.containsKey('passwordHash'), false);
      expect(j['email'], 'a@b.c');
    });
  });

  group('App.fromRow', () {
    test('parses all fields', () {
      final r = _row({
        'id': 'a1',
        'owner_id': 'u1',
        'slug': 'com.acme.app',
        'name': 'Acme',
        'platform': 'android',
        'sdk_key_prefix': 'pfk_abc',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
      });
      final a = App.fromRow(r);
      expect(a.slug, 'com.acme.app');
      expect(a.platform, 'android');
      expect(a.sdkKeyPrefix, 'pfk_abc');
    });
  });

  group('Patch.fromRow', () {
    test('parses all fields', () {
      final r = _row({
        'id': 'p1',
        'release_id': 'r1',
        'patch_number': 1,
        'file_path': 'r1/1_abc.so',
        'file_size_bytes': 1024,
        'sha256_hash': 'a' * 64,
        'signature': 'sig',
        'rollout_percent': 100,
        'is_active': true,
        'is_delta': false,
        'download_count': 0,
        'created_at': '2024-01-01T00:00:00.000Z',
      });
      final p = Patch.fromRow(r);
      expect(p.patchNumber, 1);
      expect(p.sha256Hash, 'a' * 64);
      expect(p.isActive, true);
    });

    test('toManifestJson includes required fields', () {
      final p = Patch(
        id: 'p1',
        releaseId: 'r1',
        patchNumber: 1,
        filePath: 'r1/1_abc.so',
        fileSizeBytes: 1024,
        sha256Hash: 'a' * 64,
        signature: 'sig',
        rolloutPercent: 100,
        isActive: true,
        isDelta: false,
        downloadCount: 0,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );
      final m = p.toManifestJson(downloadUrl: 'https://x/y');
      expect(m['downloadUrl'], 'https://x/y');
      expect(m['sha256'], 'a' * 64);
      expect(m['sizeBytes'], 1024);
    });
  });

  group('Release.fromRow', () {
    test('defaults channelName to stable if missing', () {
      final r = _row({
        'id': 'r1',
        'app_id': 'a1',
        'channel_id': 'c1',
        'version': '1.0.0',
        'is_active': true,
        'created_at': '2024-01-01T00:00:00.000Z',
      });
      final rel = Release.fromRow(r);
      expect(rel.channelName, 'stable');
      expect(rel.isActive, true);
    });
  });
}
