import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_encrypted_backup.dart';

void main() {
  test('encrypted backup roundtrip, randomization and authentication', () async {
    final codec = BastionEncryptedBackup();
    const payload = '{"channels":["secret key"],"name":"☃"}';
    const password = 'a long backup password';
    final a = await codec.encrypt(payload, password);
    final b = await codec.encrypt(payload, password);
    expect(a, isNot(b));
    expect(a, isNot(contains('secret key')));
    expect(await codec.decrypt(a, password), payload);
    await expectLater(codec.decrypt(a, 'incorrect password'), throwsFormatException);
    final modified = jsonDecode(a) as Map<String, dynamic>;
    final ciphertext = base64Decode(modified['ciphertext'] as String);
    ciphertext[0] ^= 1;
    modified['ciphertext'] = base64Encode(ciphertext);
    await expectLater(codec.decrypt(jsonEncode(modified), password), throwsFormatException);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('refuses plaintext, unknown version, short password, huge inputs', () async {
    final codec = BastionEncryptedBackup();
    await expectLater(codec.decrypt('{}', 'password'), throwsFormatException);
    await expectLater(codec.encrypt('data', 'short'), throwsFormatException);
    await expectLater(codec.decrypt('x' * (BastionEncryptedBackup.maxBytes * 2 + 1), 'password'), throwsFormatException);
  });
}
