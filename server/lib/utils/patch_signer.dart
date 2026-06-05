// Ed25519 signing/verification for patches.
//
// Uses the ed25519_edwards package directly because pointycastle 3.x
// doesn't ship ed25519 support.
//
// Keys are 32 bytes each (seed + public key in RFC 8032 form).

import 'dart:convert';
import 'dart:typed_data';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

class PatchSigner {
  final ed.PrivateKey _privateKey;
  final ed.PublicKey _publicKey;
  final String _publicKeyBase64;

  PatchSigner._(this._privateKey, this._publicKey, this._publicKeyBase64);

  /// Load from base64-encoded raw key bytes (32 bytes each).
  factory PatchSigner.fromBase64({
    required String privateKeyB64,
    required String publicKeyB64,
  }) {
    final seed = base64Decode(privateKeyB64);
    final pub = base64Decode(publicKeyB64);
    if (seed.length != 32 || pub.length != 32) {
      throw ArgumentError(
        'Ed25519 keys must be 32 bytes each (got priv=${seed.length}, pub=${pub.length})',
      );
    }
    // Build a PrivateKey from the seed (32 bytes) — ed25519_edwards
    // derives the public key internally.
    final priv = ed.newKeyFromSeed(Uint8List.fromList(seed));
    return PatchSigner._(
      priv,
      ed.PublicKey(pub),
      publicKeyB64,
    );
  }

  /// Sign a hex-encoded sha256 hash. Returns base64-encoded signature (64 bytes).
  String sign(String hashHex) {
    final hashBytes = Uint8List.fromList(_hexToBytes(hashHex));
    final sig = ed.sign(_privateKey, hashBytes);
    return base64Encode(sig);
  }

  /// Verify a signature. The signature is base64-encoded.
  bool verify({required String hashHex, required String signatureB64}) {
    try {
      final hashBytes = Uint8List.fromList(_hexToBytes(hashHex));
      final sigBytes = base64Decode(signatureB64);
      if (sigBytes.length != 64) return false;
      return ed.verify(_publicKey, hashBytes, Uint8List.fromList(sigBytes));
    } catch (_) {
      return false;
    }
  }

  /// The public key the SDK should embed.
  String get publicKeyBase64 => _publicKeyBase64;

  static List<int> _hexToBytes(String hex) {
    if (hex.length % 2 != 0) throw ArgumentError('odd-length hex');
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
