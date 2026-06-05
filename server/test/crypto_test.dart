// Tests for ed25519 sign/verify + key generation roundtrip.

import 'dart:convert';
import 'package:test/test.dart';
import 'package:patchfly_server/utils/keygen.dart';
import 'package:patchfly_server/utils/patch_signer.dart';

void main() {
  group('ed25519 keygen + sign/verify roundtrip', () {
    test('generated keys produce valid signatures', () {
      final kp = generateKeyPair();
      final signer = PatchSigner.fromBase64(
        privateKeyB64: kp.privateKeyB64,
        publicKeyB64: kp.publicKeyB64,
      );
      final hash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'; // sha256("")

      final sig = signer.sign(hash);
      expect(sig, isNotEmpty);
      final decoded = base64Decode(sig);
      expect(decoded.length, 64);

      final ok = signer.verify(hashHex: hash, signatureB64: sig);
      expect(ok, isTrue);
    });

    test('verification fails when signature is wrong', () {
      final kp = generateKeyPair();
      final signer = PatchSigner.fromBase64(
        privateKeyB64: kp.privateKeyB64,
        publicKeyB64: kp.publicKeyB64,
      );
      final hash = 'a' * 64;
      final sig = signer.sign(hash);
      // Tamper with the signature
      final tampered = sig.substring(0, sig.length - 4) + 'AAAA';
      final ok = signer.verify(hashHex: hash, signatureB64: tampered);
      expect(ok, isFalse);
    });

    test('verification fails when using wrong public key', () {
      final alice = generateKeyPair();
      final bob = generateKeyPair();
      final aliceSigner = PatchSigner.fromBase64(
        privateKeyB64: alice.privateKeyB64,
        publicKeyB64: alice.publicKeyB64,
      );
      // Bob verifies a signature Alice made using Bob's public key —
      // should fail.
      final bobSigner = PatchSigner.fromBase64(
        privateKeyB64: bob.privateKeyB64,
        publicKeyB64: bob.publicKeyB64,
      );
      final hash = 'b' * 64;
      final sig = aliceSigner.sign(hash);
      final ok = bobSigner.verify(hashHex: hash, signatureB64: sig);
      expect(ok, isFalse);
    });

    test('handles 32-byte key requirement', () {
      expect(
        () => PatchSigner.fromBase64(
          privateKeyB64: base64Encode(List.filled(16, 0)),
          publicKeyB64: base64Encode(List.filled(32, 0)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
