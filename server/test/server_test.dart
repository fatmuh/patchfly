// Basic smoke tests for the server.
// Run: dart test

import 'package:test/test.dart';
import 'package:patchfly_server/utils/json.dart';
import 'package:patchfly_server/utils/hash.dart';

void main() {
  group('JsonUtils', () {
    test('decodeMap parses valid JSON object', () {
      final m = JsonUtils.decodeMap('{"a": 1, "b": "x"}');
      expect(m['a'], 1);
      expect(m['b'], 'x');
    });

    test('decodeMap throws on non-object', () {
      expect(() => JsonUtils.decodeMap('[1,2,3]'), throwsFormatException);
    });
  });

  group('Validation', () {
    test('requireString returns value when present', () {
      final m = {'name': 'foo'};
      expect(Validation.requireString(m, 'name'), 'foo');
    });

    test('requireString throws when missing', () {
      expect(
        () => Validation.requireString({}, 'name'),
        throwsA(isA<BadRequest>()),
      );
    });

    test('requireString throws when empty', () {
      expect(
        () => Validation.requireString({'name': ''}, 'name'),
        throwsA(isA<BadRequest>()),
      );
    });

    test('requireString enforces min length', () {
      expect(
        () => Validation.requireString({'n': 'ab'}, 'n', min: 3),
        throwsA(isA<BadRequest>()),
      );
    });

    test('optionalInt parses int and string-int', () {
      expect(Validation.optionalInt({'i': 42}, 'i'), 42);
      expect(Validation.optionalInt({'i': '42'}, 'i'), 42);
      expect(Validation.optionalInt({}, 'i'), null);
    });

    test('optionalInt returns null on non-numeric string', () {
      // String that doesn't parse returns null (not an error) — matches
      // int.tryParse semantics, useful for optional config fields.
      expect(Validation.optionalInt({'i': 'abc'}, 'i'), null);
    });

    test('optionalInt throws on non-string non-int value', () {
      expect(
        () => Validation.optionalInt({'i': [1, 2]}, 'i'),
        throwsA(isA<BadRequest>()),
      );
    });

    test('optionalEmail validates', () {
      expect(Validation.optionalEmail({'e': 'a@b.c'}, 'e'), 'a@b.c');
      expect(
        () => Validation.optionalEmail({'e': 'notanemail'}, 'e'),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('Hash', () {
    test('sha256Hex produces known digest', () {
      // sha256 of "abc"
      expect(sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });
}
