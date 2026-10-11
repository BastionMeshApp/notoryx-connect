import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/generated/meshtastic/admin.pb.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/generated/meshtastic/channel.pb.dart';
import 'package:bastion/generated/meshtastic/mesh.pb.dart';
import 'package:bastion/generated/meshtastic/module_config.pb.dart';
import 'package:bastion/services/bastion_radio_backup.dart';

class FakeRadio implements RadioBackupGateway {
  final events = <String>[];
  bool mismatch = false;
  bool failWrite = false;
  List<AdminMessage_ConfigType> types = [AdminMessage_ConfigType.LORA_CONFIG];
  RadioBackupSnapshot snapshot = RadioBackupSnapshot(
    owner: User(longName: 'Radio ☃', shortName: 'R'),
    configs: [Config(lora: Config_LoRaConfig(hopLimit: 3))], modules: [],
    channels: [for (var i = 0; i < 8; i++) Channel(index: i,
      role: i == 0 ? Channel_Role.PRIMARY : Channel_Role.DISABLED,
      settings: ChannelSettings(psk: i == 0 ? [1] : []))],
    firmware: '2.7.16', nodeNum: 7, createdAt: DateTime.utc(2026));
  @override int get backupNodeNum => 7;
  @override String get backupFirmware => '2.7.16';
  @override List<AdminMessage_ConfigType> get backupConfigTypes => types;
  @override List<AdminMessage_ModuleConfigType> get backupModuleTypes => [];
  @override Future<User> readOwner() async { events.add('read-owner'); return snapshot.owner; }
  @override Future<Config> readConfig(AdminMessage_ConfigType type) async {
    events.add('read-config');
    return mismatch && events.contains('write') ? Config(lora: Config_LoRaConfig(hopLimit: 2)) : snapshot.configs.first;
  }
  @override Future<ModuleConfig> readModuleConfig(AdminMessage_ModuleConfigType type) async => throw UnimplementedError();
  @override Future<Channel> readChannel(int index) async => snapshot.channels[index];
  @override Future<void> waitForBackupRadio(int nodeNum) async { events.add('wait'); }
  @override Future<void> writeBackup(RadioBackupSnapshot value) async {
    events.add('write');
    if (failWrite) throw StateError('NAK');
    snapshot = value;
  }
}
void main() {
  test('snapshot roundtrip preserves every backed-up field', () async {
    final r = FakeRadio();
    final snapshot = await BastionRadioBackup(r).capture();
    final encoded = await snapshot.encode();
    final decoded = await RadioBackupSnapshot.decode(encoded);
    expect(await decoded.encode(), encoded);
    expect(decoded.channels.first.settings.psk, [1]);
  });
  test('restore only succeeds after preflight, write, reconnect and matching readback', () async {
    final r = FakeRadio();
    await BastionRadioBackup(r).restore(r.snapshot);
    expect(r.events, ['read-owner', 'read-config', 'write', 'wait', 'read-owner', 'read-config']);
  });
  test('readback mismatch and NAK never report successful restore', () async {
    final r = FakeRadio()..mismatch = true;
    await expectLater(BastionRadioBackup(r).restore(r.snapshot), throwsStateError);
    final failed = FakeRadio()..failWrite = true;
    await expectLater(BastionRadioBackup(failed).restore(failed.snapshot), throwsStateError);
    expect(failed.events, isNot(contains('wait')));
  });
  test('unsupported target sections and duplicate slots fail before any write', () async {
    final r = FakeRadio()..types = [];
    await expectLater(BastionRadioBackup(r).restore(r.snapshot), throwsFormatException);
    expect(r.events, isEmpty);
    final invalid = FakeRadio();
    invalid.snapshot.channels[7].index = 0;
    await expectLater(BastionRadioBackup(invalid).restore(invalid.snapshot), throwsFormatException);
    expect(invalid.events, isEmpty);
  });
  test('refuses identity keys and session credentials', () {
    expect(() => RadioBackupSnapshot.configType(Config(security: Config_SecurityConfig())), throwsFormatException);
    expect(() => RadioBackupSnapshot.configType(Config(sessionkey: Config_SessionkeyConfig())), throwsFormatException);
  });
}
