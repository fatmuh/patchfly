// CLI config: stores credentials & server URL in ~/.patchfly/config.json

import 'dart:convert';
import 'dart:io';

class CliConfig {
  final String? server;
  final String? token;        // JWT
  final String? apiKey;       // API key
  final String? userEmail;
  final String? currentAppId; // last-used app
  final String? currentAppSlug;

  CliConfig({
    this.server,
    this.token,
    this.apiKey,
    this.userEmail,
    this.currentAppId,
    this.currentAppSlug,
  });

  Map<String, dynamic> toJson() => {
        'server': server,
        'token': token,
        'apiKey': apiKey,
        'userEmail': userEmail,
        'currentAppId': currentAppId,
        'currentAppSlug': currentAppSlug,
      };

  factory CliConfig.fromJson(Map<String, dynamic> j) => CliConfig(
        server: j['server'] as String?,
        token: j['token'] as String?,
        apiKey: j['apiKey'] as String?,
        userEmail: j['userEmail'] as String?,
        currentAppId: j['currentAppId'] as String?,
        currentAppSlug: j['currentAppSlug'] as String?,
      );

  CliConfig copyWith({
    String? server,
    String? token,
    String? apiKey,
    String? userEmail,
    String? currentAppId,
    String? currentAppSlug,
  }) =>
      CliConfig(
        server: server ?? this.server,
        token: token ?? this.token,
        apiKey: apiKey ?? this.apiKey,
        userEmail: userEmail ?? this.userEmail,
        currentAppId: currentAppId ?? this.currentAppId,
        currentAppSlug: currentAppSlug ?? this.currentAppSlug,
      );

  String get authHeader {
    if (apiKey != null) return 'Bearer $apiKey';
    if (token != null) return 'Bearer $token';
    return '';
  }
}

class ConfigStore {
  static Directory? _configDir;
  static File? _configFile;

  static File get file {
    if (_configFile != null) return _configFile!;
    _configFile = File('${dir.path}/config.json');
    return _configFile!;
  }

  static Directory get dir {
    if (_configDir != null) return _configDir!;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    _configDir = Directory('$home/.patchfly');
    return _configDir!;
  }

  static Future<CliConfig> load() async {
    if (!await file.exists()) {
      return CliConfig();
    }
    try {
      final raw = await file.readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return CliConfig.fromJson(j);
    } catch (_) {
      // Corrupt config; return empty
      return CliConfig();
    }
  }

  static Future<void> save(CliConfig cfg) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(cfg.toJson()));
    // chmod 600 on POSIX
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }

  static String resolveServer(CliConfig cfg) {
    if (cfg.server != null && cfg.server!.isNotEmpty) return cfg.server!;
    final env = Platform.environment['PATCHFLY_SERVER'];
    if (env != null && env.isNotEmpty) return env;
    return 'http://localhost:8080';
  }
}
