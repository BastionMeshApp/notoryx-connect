import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/app_version.dart';
import 'package:bastion/services/bastion_radio_backup.dart';
import 'bastion_radio_backup_test.dart' show FakeRadio;

void main() {
  test('app version constant matches pubspec.yaml', () {
    final match = RegExp(r'^version: (\S+)$', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(match?.group(1), bastionAppVersion);
  });
  test('backups record the current app version', () async {
    final encoded = await BastionRadioBackup(FakeRadio()).capture().then((s) => s.encode());
    expect((jsonDecode(encoded) as Map)['appVersion'], bastionAppVersion);
  });
}
