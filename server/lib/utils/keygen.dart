// Ed25519 keypair generation.

import 'dart:convert';
import 'dart:typed_data';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

class GeneratedKeyPair {
  final String publicKeyB64;
  final String privateKeyB64; // 32-byte seed
  const GeneratedKeyPair(this.publicKeyB64, this.privateKeyB64);
}

/// Generate a fresh ed25519 keypair. Returns base64-encoded raw bytes.
GeneratedKeyPair generateKeyPair() {
  final kp = ed.generateKey();
  // The first 32 bytes of the expanded private key is the seed.
  final seed = Uint8List.fromList(kp.privateKey.bytes.sublist(0, 32));
  final pub = Uint8List.fromList(kp.publicKey.bytes);
  return GeneratedKeyPair(
    base64Encode(pub),
    base64Encode(seed),
  );
}
