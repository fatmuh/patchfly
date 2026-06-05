// JSON helpers & validation.

import 'dart:convert';

class JsonUtils {
  static String encode(Object? value) => jsonEncode(value);

  static Map<String, dynamic> decodeMap(String body) {
    final v = jsonDecode(body);
    if (v is! Map<String, dynamic>) {
      throw FormatException('Expected JSON object, got ${v.runtimeType}');
    }
    return v;
  }

  /// Decode possibly-null JSON for optional fields.
  static Map<String, dynamic>? decodeMapOrNull(String? body) {
    if (body == null || body.isEmpty) return null;
    return decodeMap(body);
  }
}

class Validation {
  static String requireString(Map<String, dynamic> j, String key, {int? min, int? max}) {
    final v = j[key];
    if (v is! String || v.isEmpty) {
      throw BadRequest('$key is required and must be a non-empty string');
    }
    if (min != null && v.length < min) {
      throw BadRequest('$key must be at least $min characters');
    }
    if (max != null && v.length > max) {
      throw BadRequest('$key must be at most $max characters');
    }
    return v;
  }

  static String? optionalString(Map<String, dynamic> j, String key, {int? max}) {
    final v = j[key];
    if (v == null) return null;
    if (v is! String) throw BadRequest('$key must be a string');
    if (max != null && v.length > max) {
      throw BadRequest('$key must be at most $max characters');
    }
    return v.isEmpty ? null : v;
  }

  static int? optionalInt(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    throw BadRequest('$key must be an integer');
  }

  static bool? optionalBool(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v == null) return null;
    if (v is bool) return v;
    throw BadRequest('$key must be a boolean');
  }

  static String? optionalEmail(Map<String, dynamic> j, String key) {
    final v = optionalString(j, key, max: 254);
    if (v == null) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      throw BadRequest('$key must be a valid email');
    }
    return v.toLowerCase();
  }
}

class BadRequest implements Exception {
  final String message;
  BadRequest(this.message);
  @override
  String toString() => 'BadRequest: $message';
}

class NotFound implements Exception {
  final String message;
  NotFound([this.message = 'Not found']);
  @override
  String toString() => 'NotFound: $message';
}

class Conflict implements Exception {
  final String message;
  Conflict(this.message);
  @override
  String toString() => 'Conflict: $message';
}
