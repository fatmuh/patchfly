// HTTP client for talking to the Patchfly server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;
  final String? code;
  final dynamic body;
  ApiException(this.status, this.message, {this.code, this.body});

  @override
  String toString() => 'ApiException($status $code): $message';
}

class ApiClient {
  final String baseUrl;
  final String Function() _authHeader;
  final http.Client _http;

  ApiClient({
    required this.baseUrl,
    required String Function() authHeader,
    http.Client? client,
  })  : _authHeader = authHeader,
        _http = client ?? http.Client();

  Map<String, String> _headers({bool json = true, bool auth = true}) {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    if (auth) {
      final a = _authHeader();
      if (a.isNotEmpty) h['authorization'] = a;
    }
    return h;
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final r = await _http
        .get(uri, headers: _headers(json: false))
        .timeout(const Duration(seconds: 30));
    return _parse(r);
  }

  Future<dynamic> post(String path, [Object? body]) async {
    final r = await _http
        .post(Uri.parse('$baseUrl$path'),
            headers: _headers(),
            body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    return _parse(r);
  }

  Future<dynamic> patch(String path, Object body) async {
    final r = await _http
        .patch(Uri.parse('$baseUrl$path'),
            headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    return _parse(r);
  }

  Future<dynamic> delete(String path) async {
    final r = await _http
        .delete(Uri.parse('$baseUrl$path'), headers: _headers(json: false))
        .timeout(const Duration(seconds: 30));
    return _parse(r);
  }

  /// Upload a multipart file (patch upload).
  Future<dynamic> uploadMultipart(
    String path, {
    required File file,
    required String fieldName,
    required String sha256,
    int? rolloutPercent,
    String? minAppVersion,
    String? maxAppVersion,
    bool activate = true,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    final a = _authHeader();
    if (a.isNotEmpty) req.headers['authorization'] = a;
    req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    req.fields['sha256'] = sha256;
    if (rolloutPercent != null) {
      req.fields['rolloutPercent'] = rolloutPercent.toString();
    }
    if (minAppVersion != null) req.fields['minAppVersion'] = minAppVersion;
    if (maxAppVersion != null) req.fields['maxAppVersion'] = maxAppVersion;
    req.fields['activate'] = activate.toString();

    final streamed = await req.send().timeout(const Duration(minutes: 30));
    final r = await http.Response.fromStream(streamed);
    return _parse(r);
  }

  dynamic _parse(http.Response r) {
    final ct = r.headers['content-type'] ?? '';
    dynamic body;
    if (ct.contains('application/json') && r.body.isNotEmpty) {
      try {
        body = jsonDecode(r.body);
      } catch (_) {
        body = r.body;
      }
    } else {
      body = r.body;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return body;
    }
    final msg = body is Map && body['message'] is String
        ? body['message'] as String
        : 'HTTP ${r.statusCode}';
    final code = body is Map ? body['error'] as String? : null;
    throw ApiException(r.statusCode, msg, code: code, body: body);
  }

  void close() => _http.close();
}

/// Helper to make a client from current config.
ApiClient clientFromConfig() {
  // We can't easily await here, but the load is sync-ish via ConfigStore.
  // In practice, callers should await load and pass the cfg.
  throw UnimplementedError(
      'Use ApiClient.fromConfig(cfg) and pass the loaded config');
}
