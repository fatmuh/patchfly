// Generate ed25519 key pair for signing patches.
//
// Usage:
//   cd server
//   dart run tool/gen_signing_keys.dart
//
// Then copy the output to your .env file.

import 'package:patchfly_server/utils/keygen.dart';

void main() {
  final kp = generateKeyPair();
  // ignore_for_file: avoid_print
  print('# Patchfly signing keys');
  print('# Generated: ${DateTime.now().toIso8601String()}');
  print('# IMPORTANT: treat the private key as a secret.');
  print('# Store it in a password manager or secret manager.');
  print('');
  print('PATCH_SIGNING_PUBLIC_KEY=${kp.publicKeyB64}');
  print('PATCH_SIGNING_PRIVATE_KEY=${kp.privateKeyB64}');
}
