// Password hashing & token utilities.

import 'dart:math';
import 'dart:typed_data';
import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class PasswordHasher {
  /// Hash password with bcrypt.
  static String hash(String password) {
    final salt = BCrypt.gensalt();
    return BCrypt.hashpw(password, salt);
  }

  static bool verify(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (_) {
      return false;
    }
  }
}

/// SHA256 of a string, returns lowercase hex.
String sha256Hex(String input) {
  final bytes = utf8.encode(input);
  return sha256.convert(bytes).toString();
}

/// SHA256 of bytes, returns lowercase hex.
String sha256BytesHex(List<int> bytes) {
  return sha256.convert(bytes).toString();
}

/// Generate a random token (URL-safe). Used for API keys.
String randomToken({int bytes = 32}) {
  final rng = Random.secure();
  final values = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    values[i] = rng.nextInt(256);
  }
  return base64Url.encode(values).replaceAll('=', '');
}

/// Extract a short prefix of a token for display: "abc12345..."
String tokenPrefix(String token, {int chars = 8}) {
  return token.length <= chars ? token : token.substring(0, chars);
}
