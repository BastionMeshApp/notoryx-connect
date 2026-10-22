import 'dart:convert';

import 'package:bastion/phone_backup_page.dart';
import 'package:bastion/services/bastion_encrypted_backup.dart';
import 'package:bastion/services/bastion_message_archive.dart';
import 'package:bastion/services/bastion_phone_backup.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final class FlakyStore extends InMemorySharedPreferencesAsync {
  FlakyStore() : super.empty();
  String? failWriteKey;
  @override
  Future<bool> setString(String key, String value, SharedPreferencesOptions options) async {
    if (key == failWriteKey) throw StateError('disk full');
    return super.setString(key, value, options);
  }
}

class _Files implements PhoneBackupFiles {
  String? saved;
  String? toOpen;
  @override Future<void> save(String fileName, String text) async => saved = text;
  @override Future<String?> open() async => toOpen;
}

void main() {
  late FlakyStore store;
  late SharedPreferencesAsync prefs;

  setUp(() {
    store = FlakyStore();
    SharedPreferencesAsyncPlatform.instance = store;
    prefs = SharedPreferencesAsync();
  });

  Future<void> seed() async {
    await prefs.setString(BastionMessageArchive.radioKey(0xA1), jsonEncode({
      'messages': [{'text': 'a'}, {'text': 'b'}], 'pending': []}));
    await prefs.setString('bastion.nodedex.annotations.v1', '{"7":{"favorite":true,"note":"gate"}}');
    await prefs.setInt('bastion.comms.last_radio', 0xA1);
    await prefs.setBool('bastion.low_power_mode', true);
    await prefs.setString('other.app.key', 'not ours');
  }

  test('round trip restores every app item exactly and nothing else', () async {
    await seed();
    final plain = await BastionPhoneBackup().export(now: DateTime.utc(2026, 10, 21, 15));
    final (summary, values) = BastionPhoneBackup.parse(plain);
    expect(summary.radios, 1);
    expect(summary.messages, 2);
    expect(summary.items, 4, reason: 'only bastion.* keys');
    expect(values.containsKey('other.app.key'), isFalse);

    await prefs.setBool('bastion.low_power_mode', false);
    await prefs.setString('bastion.waypoints', 'added after backup');
    await BastionPhoneBackup().restore(values);

    expect(await prefs.getBool('bastion.low_power_mode'), isTrue);
    expect(await prefs.getInt('bastion.comms.last_radio'), 0xA1);
    expect(await prefs.getString('bastion.waypoints'), isNull, reason: 'replace, not merge');
    expect(await prefs.getString('other.app.key'), 'not ours');
    expect(await BastionPhoneBackup().export(now: DateTime.utc(2026, 10, 21, 15)), plain);
  });

  test('refuses newer, foreign and damaged backups before changing anything', () {
    Map<String, Object?> doc({Object? version = 1, Map<String, Object?>? entries}) => {
      'format': BastionPhoneBackup.format, 'formatVersion': version,
      'exportedAtUtc': '2026-10-21T15:00:00Z', 'entries': entries ?? {}};
    expect(() => BastionPhoneBackup.parse(jsonEncode(doc(version: 2))),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('newer version'))));
    expect(() => BastionPhoneBackup.parse('{"format":"bastion-radio-settings"}'), throwsFormatException);
    expect(() => BastionPhoneBackup.parse('not json'), throwsFormatException);
    expect(() => BastionPhoneBackup.parse(jsonEncode(doc(entries: {'other.key': {'type': 'string', 'value': 'x'}}))),
        throwsFormatException);
    expect(() => BastionPhoneBackup.parse(jsonEncode(doc(entries: {'bastion.theme': {'type': 'int', 'value': 'dark'}}))),
        throwsFormatException);
  });

  test('a failed write puts the previous phone data back', () async {
    await seed();
    final (_, values) = BastionPhoneBackup.parse(await BastionPhoneBackup().export());
    final restoreValues = {...values, 'bastion.waypoints': 'from backup'};
    await prefs.setBool('bastion.low_power_mode', false);
    await prefs.setString('bastion.theme', 'light');
    store.failWriteKey = 'bastion.waypoints';

    await expectLater(BastionPhoneBackup().restore(restoreValues),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('previous phone data was put back'))));
    expect(await prefs.getBool('bastion.low_power_mode'), isFalse);
    expect(await prefs.getString('bastion.theme'), 'light');
    expect(await prefs.getString('bastion.waypoints'), isNull);
  });

  test('phone and radio backups cannot be swapped', () async {
    const password = 'correct horse battery';
    final phone = await BastionPhoneBackup.encryption.encrypt('{}', password);
    await expectLater(const BastionEncryptedBackup().decrypt(phone, password), throwsFormatException);
    final radio = await const BastionEncryptedBackup().encrypt('{}', password);
    await expectLater(BastionPhoneBackup.encryption.decrypt(radio, password), throwsFormatException);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('restore is refused while a radio is connected', (tester) async {
    final radio = MeshtasticRadioCoordinator();
    addTearDown(radio.dispose);
    radio.connection.beginConnect('Field Radio');
    final files = _Files()..toOpen = 'unused';
    await tester.pumpWidget(MaterialApp(home: PhoneBackupPage(radio: radio, files: files)));
    await tester.enterText(find.byType(TextField), 'correct horse battery');
    await tester.tap(find.text('Restore from file'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect the radio before restoring phone data.'), findsOneWidget);
  });
}
