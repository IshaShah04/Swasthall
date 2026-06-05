import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class EncryptionUtils {
  static const int _ivLength = 12;
  static const int _tagLength = 16;

  /// Encrypts plaintext with AES-256-GCM.
  /// Returns base64(iv + ciphertext + tag).
  static String encrypt(String plaintext, Uint8List key) {
    final iv = _generateIV();
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagLength * 8, iv, Uint8List(0)),
      );

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = Uint8List(cipher.getOutputSize(input.length));
    var offset = cipher.processBytes(input, 0, input.length, output, 0);
    cipher.doFinal(output, offset);

    final combined = Uint8List(_ivLength + output.length);
    combined.setRange(0, _ivLength, iv);
    combined.setRange(_ivLength, combined.length, output);

    return base64.encode(combined);
  }

  /// Decrypts base64(iv + ciphertext + tag) back to plaintext.
  static String decrypt(String encryptedBase64, Uint8List key) {
    final combined = base64.decode(encryptedBase64);
    final iv = combined.sublist(0, _ivLength);
    final ciphertext = combined.sublist(_ivLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _tagLength * 8, iv, Uint8List(0)),
      );

    final output = Uint8List(cipher.getOutputSize(ciphertext.length));
    var offset = cipher.processBytes(ciphertext, 0, ciphertext.length, output, 0);
    cipher.doFinal(output, offset);

    return utf8.decode(output);
  }

  /// Derives a 256-bit key from uid + salt using HKDF-SHA256.
  static Future<Uint8List> deriveKey(String uid, String salt) async {
    final hkdf = HKDFKeyDerivator(SHA256Digest());
    hkdf.init(HkdfParameters(
      Uint8List.fromList(utf8.encode(uid)),
      32,
      Uint8List.fromList(utf8.encode(salt)),
      Uint8List.fromList(utf8.encode('swasthall-pii-v1')),
    ));
    final key = Uint8List(32);
    hkdf.deriveKey(null, 0, key, 0);
    return key;
  }

  static Uint8List _generateIV() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(_ivLength, (_) => random.nextInt(256)));
  }
}
