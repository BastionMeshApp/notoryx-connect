import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/channel.pb.dart';
import 'package:bastion/generated/meshtastic/config.pbenum.dart';
import 'package:bastion/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion/generated/meshtastic/mesh_beacon.pb.dart';
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/bastion_beacons.dart';
import 'package:bastion/services/meshtastic_channel_url.dart';
import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final now = DateTime.utc(2026, 10, 24, 12);

pb.MeshPacket beaconPacket(MeshBeacon beacon, {int from = 0x77, PortNum? port}) => pb.MeshPacket(
      from: from,
      rxSnr: 6.5,
      rxRssi: -98,
      decoded: pb.Data(portnum: port ?? PortNum.MESH_BEACON_APP, payload: beacon.writeToBuffer()),
    );

final trailChannel = ChannelSettings(name: 'Trail', psk: Uint8List.fromList(List.filled(16, 7)));

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  test('records a heard beacon with its offer and signal', () async {
    final log = BastionBeaconLog(clock: () => now);
    final changed = await log.handlePacket(beaconPacket(MeshBeacon(
      message: 'Ridge mesh here',
      offerChannel: trailChannel,
      offerRegion: Config_LoRaConfig_RegionCode.US,
      offerPreset: Config_LoRaConfig_ModemPreset.MEDIUM_FAST,
    )));
    expect(changed, isTrue);
    final heard = log.beacons.single;
    expect(heard.from, 0x77);
    expect(heard.message, 'Ridge mesh here');
    expect(heard.offerChannel!.name, 'Trail');
    expect(heard.offerRegion, Config_LoRaConfig_RegionCode.US);
    expect(heard.offerPreset, Config_LoRaConfig_ModemPreset.MEDIUM_FAST);
    expect(heard.offerFrequencySlot, isNull);
    expect(heard.snr, 6.5);
    expect(heard.rssi, -98);
    expect(heard.heardAt, now);
  });

  test('ignores other ports and malformed payloads', () async {
    final log = BastionBeaconLog(clock: () => now);
    expect(await log.handlePacket(beaconPacket(MeshBeacon(message: 'x'), port: PortNum.TEXT_MESSAGE_APP)), isFalse);
    expect(await log.handlePacket(pb.MeshPacket(
      from: 1,
      decoded: pb.Data(portnum: PortNum.MESH_BEACON_APP, payload: [0xff, 0xff, 0xff]),
    )), isFalse);
    expect(log.beacons, isEmpty);
  });

  test('a repeated beacon replaces the older copy and newest comes first', () async {
    var time = now;
    final log = BastionBeaconLog(clock: () => time);
    await log.handlePacket(beaconPacket(MeshBeacon(message: 'A'), from: 1));
    time = now.add(const Duration(minutes: 5));
    await log.handlePacket(beaconPacket(MeshBeacon(message: 'B'), from: 2));
    time = now.add(const Duration(hours: 1));
    await log.handlePacket(beaconPacket(MeshBeacon(message: 'A'), from: 1));
    expect(log.beacons.map((b) => b.message), ['A', 'B']);
    expect(log.beacons.first.heardAt, now.add(const Duration(hours: 1)));
  });

  test('keeps at most maxKept beacons', () async {
    final log = BastionBeaconLog(clock: () => now);
    for (var i = 0; i < BastionBeaconLog.maxKept + 5; i++) {
      await log.handlePacket(beaconPacket(MeshBeacon(message: 'm$i'), from: i + 1));
    }
    expect(log.beacons, hasLength(BastionBeaconLog.maxKept));
    expect(log.beacons.first.message, 'm${BastionBeaconLog.maxKept + 4}');
  });

  test('heard beacons and the send limit persist', () async {
    final first = BastionBeaconLog(clock: () => now);
    await first.handlePacket(beaconPacket(MeshBeacon(message: 'Kept', offerChannel: trailChannel)));
    await first.recordSent();

    final second = BastionBeaconLog(clock: () => now.add(const Duration(minutes: 10)));
    await second.load();
    expect(second.beacons.single.message, 'Kept');
    expect(second.beacons.single.offerChannel!.psk, trailChannel.psk);
    expect(second.nextSendAllowed, now.add(BastionBeaconLog.sendInterval));
  });

  test('sending is allowed again after the interval', () async {
    var time = now;
    final log = BastionBeaconLog(clock: () => time);
    expect(log.nextSendAllowed, isNull);
    await log.recordSent();
    expect(log.nextSendAllowed, isNotNull);
    time = now.add(BastionBeaconLog.sendInterval);
    expect(log.nextSendAllowed, isNull);
  });

  test('join link adds only the offered channel', () {
    final beacon = HeardBeacon(from: 1, heardAt: now, message: 'x', offerChannel: trailChannel);
    final link = beacon.joinLink!;
    expect(MeshtasticChannelUrl.isAddLink(link), isTrue);
    final set = MeshtasticChannelUrl.decode(link);
    expect(set.settings.single.name, 'Trail');
    expect(set.hasLoraConfig(), isFalse);
    expect(HeardBeacon(from: 1, heardAt: now, message: 'x').joinLink, isNull);
  });

  test('message must be non-empty and fit the firmware limit', () {
    expect(() => BastionBeaconLog.checkMessage('  '), throwsArgumentError);
    expect(() => BastionBeaconLog.checkMessage('a' * BastionBeaconLog.maxMessageBytes), returnsNormally);
    expect(() => BastionBeaconLog.checkMessage('a' * (BastionBeaconLog.maxMessageBytes + 1)), throwsArgumentError);
    // Multi-byte characters count in bytes, not characters.
    expect(() => BastionBeaconLog.checkMessage('é' * 31), throwsArgumentError);
  });

  test('encodes a broadcast MESH_BEACON_APP packet', () {
    final bytes = BastionBeaconLog.encode(MeshBeacon(message: 'Hi'), channel: 2);
    final packet = pb.ToRadio.fromBuffer(bytes).packet;
    expect(packet.to, MeshtasticTextCodec.broadcastNode);
    expect(packet.channel, 2);
    expect(packet.decoded.portnum, PortNum.MESH_BEACON_APP);
    expect(MeshBeacon.fromBuffer(packet.decoded.payload).message, 'Hi');
  });
}
