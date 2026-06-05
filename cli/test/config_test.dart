// Tests for the CLI config.

import 'package:test/test.dart';
import 'package:patchfly/src/config.dart';

void main() {
  group('CliConfig', () {
    test('toJson / fromJson roundtrip', () {
      final cfg = CliConfig(
        server: 'https://example.com',
        token: 'eyJ...',
        userEmail: 'a@b.c',
        currentAppSlug: 'com.app',
      );
      final j = cfg.toJson();
      final back = CliConfig.fromJson(j);
      expect(back.server, 'https://example.com');
      expect(back.token, 'eyJ...');
      expect(back.userEmail, 'a@b.c');
      expect(back.currentAppSlug, 'com.app');
    });

    test('authHeader prefers API key over token', () {
      final cfg = CliConfig(apiKey: 'pft_abc', token: 'eyJ.xyz');
      expect(cfg.authHeader, 'Bearer pft_abc');
    });

    test('authHeader uses token when no API key', () {
      final cfg = CliConfig(token: 'eyJ.xyz');
      expect(cfg.authHeader, 'Bearer eyJ.xyz');
    });

    test('authHeader empty when no auth', () {
      expect(CliConfig().authHeader, '');
    });

    test('copyWith preserves unchanged fields', () {
      final cfg = CliConfig(server: 'https://a', userEmail: 'x@y.z');
      final updated = cfg.copyWith(token: 'new');
      expect(updated.server, 'https://a');
      expect(updated.userEmail, 'x@y.z');
      expect(updated.token, 'new');
    });
  });
}
