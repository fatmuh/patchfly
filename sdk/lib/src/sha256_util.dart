// lib/src/sha256_util.dart
// Small wrapper around package:crypto's SHA-256.

import 'package:crypto/crypto.dart';

class Sha256Util {
  static String hash(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }
}
