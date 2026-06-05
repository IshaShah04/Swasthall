import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:swasthall/utils/encryption_utils.dart';

void main() {
  final testKey = Uint8List.fromList(List.generate(32, (i) => i));

  group('EncryptionUtils', () {
    test('encrypt-decrypt round trip returns original plaintext', () {
      const original = 'Patient has hypertension and Type 2 diabetes.';
      final encrypted = EncryptionUtils.encrypt(original, testKey);
      final decrypted = EncryptionUtils.decrypt(encrypted, testKey);
      expect(decrypted, equals(original));
    });

    test('wrong key produces invalid output or throws', () {
      const original = 'Sensitive data';
      final encrypted = EncryptionUtils.encrypt(original, testKey);
      final wrongKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      expect(
        () => EncryptionUtils.decrypt(encrypted, wrongKey),
        throwsA(anything),
      );
    });

    test('empty string encrypts and decrypts correctly', () {
      const original = '';
      final encrypted = EncryptionUtils.encrypt(original, testKey);
      final decrypted = EncryptionUtils.decrypt(encrypted, testKey);
      expect(decrypted, equals(original));
    });

    test('two encryptions of same plaintext produce different ciphertext (IV randomness)', () {
      const original = 'Same text';
      final enc1 = EncryptionUtils.encrypt(original, testKey);
      final enc2 = EncryptionUtils.encrypt(original, testKey);
      expect(enc1, isNot(equals(enc2)));
    });
  });
}
