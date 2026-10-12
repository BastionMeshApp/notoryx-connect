import 'dart:async';
import 'package:fixnum/fixnum.dart';
import 'package:bastion/services/bastion_settings_verifier.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/generated/meshtastic/channel.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero preset and omitted false values compare by meaning', () {
    final before = Config_LoRaConfig(usePreset: true, txEnabled: true, modemPreset: Config_LoRaConfig_ModemPreset.LONG_SLOW);
    final wanted = Config_LoRaConfig(usePreset: true, txEnabled: false, modemPreset: Config_LoRaConfig_ModemPreset.LONG_FAST);
    final actual = Config_LoRaConfig(usePreset: true); // Long Fast/false omitted on wire.
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, actual), isTrue);
    actual.txEnabled = true;
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, actual), isFalse);
  });
  test('unknown preset wire values cannot masquerade as a confirmed default', () {
    final before = Config_LoRaConfig()..unknownFields.mergeVarintField(2, Int64(999));
    final wanted = before.deepCopy()..modemPreset = Config_LoRaConfig_ModemPreset.LONG_FAST;
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, before), isFalse);
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, Config_LoRaConfig()), isTrue);
  });
  test('only edited fields are checked; unrelated firmware normalization is allowed', () {
    final before = Config_LoRaConfig(hopLimit: 3, bandwidth: 250);
    final wanted = Config_LoRaConfig(hopLimit: 4, bandwidth: 250);
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, Config_LoRaConfig(hopLimit: 4, bandwidth: 0)), isTrue);
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, before), isFalse);
  });
  test('nested channel keys and slot zero are compared without leaking values', () {
    final before = Channel(index: 0, settings: ChannelSettings(name: 'Old', psk: [1]));
    final wanted = Channel(index: 0, settings: ChannelSettings(name: 'New', psk: [2]));
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, Channel(settings: ChannelSettings(name: 'New', psk: [2]))), isTrue);
    expect(BastionSettingsVerifier.matchesChanges(before, wanted, Channel(settings: ChannelSettings(name: 'New', psk: [1]))), isFalse);
  });
  test('save writes once, waits and reads; ACK alone is not success', () async {
    var node = 42; final events = <String>[];
    final before = Config_LoRaConfig(hopLimit: 3), wanted = Config_LoRaConfig(hopLimit: 4);
    Future<Config_LoRaConfig> save(Config_LoRaConfig actual) => BastionSettingsVerifier.save(
      node: 42, currentNode: () => node, original: before, requested: wanted,
      write: () async { events.add('write'); node = 0; },
      waitForRadio: (target) async { events.add('wait:$target'); node = target; },
      read: () async { events.add('read'); return actual; });
    await expectLater(save(before), throwsStateError);
    expect(events, ['write', 'wait:42', 'read']);
    events.clear(); await save(wanted);
    expect(events, ['write', 'wait:42', 'read']);
  });
  test('wrong radio and reconnect timeout never resend', () async {
    var node = 42, writes = 0, reads = 0;
    final before = Config_LoRaConfig(hopLimit: 3), wanted = Config_LoRaConfig(hopLimit: 4);
    Future<void> run(Future<void> Function(int) wait) async {
      await BastionSettingsVerifier.save(node: 42, currentNode: () => node,
        original: before, requested: wanted, write: () async { writes++; },
        waitForRadio: wait, read: () async { reads++; return wanted; });
    }
    await expectLater(run((_) async { node = 99; }), throwsStateError);
    expect(writes, 1); expect(reads, 0);
    node = 42;
    await expectLater(run((_) async { throw TimeoutException('Not reconnected'); }), throwsA(isA<TimeoutException>()));
    expect(writes, 2); expect(reads, 0);
    node = 99;
    await expectLater(run((_) async {}), throwsStateError);
    expect(writes, 2);
  });
}
