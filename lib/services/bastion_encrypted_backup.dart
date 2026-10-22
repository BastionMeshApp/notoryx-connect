import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Authenticated, password-protected backups. Plaintext never reaches storage.
class BastionEncryptedBackup {
  /// [format] labels and authenticates the content, so one kind of backup
  /// can never be decrypted as another. Defaults are the radio settings backup.
  const BastionEncryptedBackup({
    this.format = 'bastion-encrypted-radio-backup',
    this.maxBytes = 1024 * 1024,
  });

  static const iterations = 600000;
  final String format;
  final int maxBytes;
  String get _format => format;
  String get _aad => '$format:1';
  static final _cipher = AesGcm.with256bits();

  Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: salt);

  /// Uses a fresh salt and nonce for every backup, even with the same password.
  Future<String> encrypt(String payload, String password) async {
    if (password.length < 12) {
      throw const FormatException('Use a backup password of at least 12 characters.');
    }
    final bytes = utf8.encode(payload);
    if (bytes.length > maxBytes) throw const FormatException('Backup is too large.');
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final box = await _cipher.encrypt(bytes, secretKey: await _key(password, salt),
        aad: utf8.encode(_aad));
    return jsonEncode({'format': _format, 'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256', 'iterations': iterations,
      'salt': base64Encode(salt), 'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText), 'mac': base64Encode(box.mac.bytes)});
  }

  /// Rejects modified ciphertext, unsupported parameters, and wrong passwords.
  Future<String> decrypt(String text, String password) async {
    if (text.length > maxBytes * 2) throw const FormatException('Backup is too large.');
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> || decoded['format'] != _format ||
        decoded['version'] != 1 || decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        decoded['iterations'] != iterations) {
      throw const FormatException('Unsupported encrypted backup format.');
    }
    List<int> bytes(String field) {
      final value = decoded[field];
      if (value is! String) throw const FormatException('Invalid encrypted backup.');
      return base64Decode(value);
    }
    final salt = bytes('salt'), nonce = bytes('nonce'), mac = bytes('mac');
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Invalid encrypted backup.');
    }
    try {
      final plain = await _cipher.decrypt(SecretBox(bytes('ciphertext'), nonce: nonce,
          mac: Mac(mac)), secretKey: await _key(password, salt), aad: utf8.encode(_aad));
      return utf8.decode(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong password or damaged backup.');
    }
  }
}
