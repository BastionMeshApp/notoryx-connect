import 'dart:async';

import 'package:bastion/generated/meshtastic/admin.pb.dart';
import 'package:bastion/generated/meshtastic/apponly.pb.dart';
import 'package:bastion/generated/meshtastic/channel.pb.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/services/bastion_channel_import.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRadio implements ChannelImportGateway {
  FakeRadio() {
    channels = [
      for (var i = 0; i < 8; i++)
        Channel(index: i, role: i == 0 ? Channel_Role.PRIMARY : Channel_Role.DISABLED,
          settings: i == 0 ? ChannelSettings(psk: [1]) : null),
    ];
  }

  late List<Channel> channels;
  Config lora = Config(lora: Config_LoRaConfig(region: Config_LoRaConfig_RegionCode.US, hopLimit: 3));
  final events = <String>[];
  int? node = 7;
  int? dropSlot;
  bool dropLora = false;
  Object? writeError;
  Object? waitError;
  int? nodeAfterWait;

  @override int? get localNodeNum => node;

  @override
  Future<Channel> readChannel(int index) async {
    events.add('read $index');
    return channels[index].deepCopy();
  }

  @override
  Future<Config> readConfig(AdminMessage_ConfigType type) async {
    events.add('read lora');
    return lora.deepCopy();
  }

  @override
  Future<void> writeChannelImport(List<Channel> writes, Config? newLora) async {
    events.add('write');
    if (writeError != null) {
      channels[writes.first.index] = writes.first;
      throw writeError!;
    }
    for (final c in writes) {
      if (c.index != dropSlot) channels[c.index] = c;
    }
    if (newLora != null && !dropLora) lora = newLora;
  }

  @override
  Future<void> waitForSettingsRadio(int nodeNum) async {
    events.add('wait $nodeNum');
    if (waitError != null) throw waitError!;
    if (nodeAfterWait != null) node = nodeAfterWait;
  }
}

ChannelSet link(List<String> names, {bool withLora = false}) => ChannelSet(
  settings: [for (final n in names) ChannelSettings(name: n, psk: [n.length])],
  loraConfig: withLora
      ? Config_LoRaConfig(region: Config_LoRaConfig_RegionCode.EU_868, hopLimit: 5)
      : null,
);

Matcher importError({required bool changed, String? mentions}) => isA<ChannelImportException>()
    .having((e) => e.radioMayHaveChanged, 'radioMayHaveChanged', changed)
    .having((e) => e.message, 'message', contains(mentions ?? ''));

void main() {
  test('add writes free slots once, then verifies them from the same radio', () async {
    final radio = FakeRadio();
    expect(await BastionChannelImport(radio).apply(link(['Trail', 'Camp']), replace: false), 2);
    expect(radio.channels[1].settings.name, 'Trail');
    expect(radio.channels[2].role, Channel_Role.SECONDARY);
    final write = radio.events.indexOf('write');
    expect(radio.events.where((e) => e == 'write'), hasLength(1));
    expect(radio.events.sublist(write + 1), ['wait 7', 'read 1', 'read 2']);
  });

  test('add skips channels already on the radio without writing', () async {
    final radio = FakeRadio();
    radio.channels[3] = Channel(index: 3, role: Channel_Role.SECONDARY,
      settings: ChannelSettings(name: 'Trail', psk: [5]));
    expect(await BastionChannelImport(radio).apply(link(['Trail']), replace: false), 0);
    expect(radio.events, isNot(contains('write')));
  });

  test('replace verifies all 8 slots and the LoRa settings', () async {
    final radio = FakeRadio();
    expect(await BastionChannelImport(radio).apply(link(['Main', 'Ops'], withLora: true), replace: true), 2);
    expect(radio.channels[0].settings.name, 'Main');
    expect(radio.channels[0].role, Channel_Role.PRIMARY);
    expect(radio.lora.lora.region, Config_LoRaConfig_RegionCode.EU_868);
    final afterWait = radio.events.sublist(radio.events.indexOf('wait 7') + 1);
    expect(afterWait, [for (var i = 0; i < 8; i++) 'read $i', 'read lora']);
  });

  test('a slot that reads back differently is reported, not resent', () async {
    final radio = FakeRadio()..dropSlot = 2;
    await expectLater(BastionChannelImport(radio).apply(link(['Trail', 'Camp']), replace: false),
      throwsA(importError(changed: true, mentions: 'slot 2')));
    expect(radio.events.where((e) => e == 'write'), hasLength(1));
  });

  test('LoRa settings that read back differently are reported', () async {
    final radio = FakeRadio()..dropLora = true;
    await expectLater(BastionChannelImport(radio).apply(link(['Main'], withLora: true), replace: true),
      throwsA(importError(changed: true, mentions: 'LoRa settings')));
  });

  test('an interrupted write is reported as possibly applied and never retried', () async {
    final radio = FakeRadio()..writeError = TimeoutException('no ACK');
    await expectLater(BastionChannelImport(radio).apply(link(['Trail', 'Camp']), replace: false),
      throwsA(importError(changed: true, mentions: 'interrupted')));
    expect(radio.events.where((e) => e == 'write'), hasLength(1));
    expect(radio.events.last, 'write', reason: 'no wait, readback or second write');
  });

  test('reconnecting to a different radio fails verification', () async {
    final radio = FakeRadio()..nodeAfterWait = 9;
    await expectLater(BastionChannelImport(radio).apply(link(['Trail']), replace: false),
      throwsA(importError(changed: true, mentions: 'could not be verified')));
    expect(radio.events.last, 'wait 7', reason: 'never reads from the other radio');
  });

  test('a reconnect timeout fails verification', () async {
    final radio = FakeRadio()..waitError = TimeoutException('Reconnect to the same radio');
    await expectLater(BastionChannelImport(radio).apply(link(['Trail']), replace: false),
      throwsA(importError(changed: true, mentions: 'Reconnect to the same radio')));
  });

  test('too few free slots or no radio refuses before any write', () async {
    final full = FakeRadio();
    for (var i = 1; i < 8; i++) {
      full.channels[i] = Channel(index: i, role: Channel_Role.SECONDARY,
        settings: ChannelSettings(name: 'C$i'));
    }
    await expectLater(BastionChannelImport(full).apply(link(['Trail']), replace: false),
      throwsA(importError(changed: false, mentions: '0 free channel slots')));
    expect(full.events, isNot(contains('write')));

    final none = FakeRadio()..node = null;
    await expectLater(BastionChannelImport(none).apply(link(['Trail']), replace: false),
      throwsA(importError(changed: false)));
    expect(none.events, isEmpty);
  });
}
