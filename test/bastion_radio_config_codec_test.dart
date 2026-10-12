import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/generated/meshtastic/channel.pb.dart';
import 'package:bastion/services/bastion_radio_config_codec.dart';

void main() {
  test('reads LoRa region preset and hop limit', () {
    // Config.lora (6) containing region (7), preset (2), hop_limit (8).
    final config = Uint8List.fromList([0x32, 0x08, 0x08, 0x01, 0x38, 0x01, 0x10, 0x03, 0x40, 0x05]);
    expect(BastionRadioConfigCodec.loraSummary(config),
        'Region: US • Preset: Medium Slow • Hop limit: 5');
  });

  test('omitted zero preset means Long Fast, not missing settings', () {
    final config = Uint8List.fromList([0x32, 0x06, 0x08, 0x01, 0x38, 0x01, 0x40, 0x07]);
    expect(BastionRadioConfigCodec.loraSummary(config),
        'Region: US • Preset: Long Fast • Hop limit: 7');
    expect(BastionRadioConfigCodec.loraSummary(Uint8List(0)), isNull);
  });

  test('unknown enum values do not masquerade as known defaults', () {
    final bytes = Uint8List.fromList([0x32, 0x06, 0x08, 0x01, 0x10, 0x63, 0x38, 0x63]);
    expect(BastionRadioConfigCodec.loraSummary(bytes),
        'Region: Unknown (99) • Preset: Unknown (99) • Hop limit: 0');
  });

  test('channel summaries are unique, ordered and replace stale rows', () {
    final zero = Uint8List.fromList([0x12, 0x00, 0x18, 0x01]);
    final first = Channel(index: 2, role: Channel_Role.SECONDARY,
        settings: ChannelSettings(name: 'Before'));
    final latest = Channel(index: 2, role: Channel_Role.DISABLED,
        settings: ChannelSettings(name: 'After'));
    expect(BastionRadioConfigCodec.channelSummaries([
      first.writeToBuffer(), zero, zero, latest.writeToBuffer(),
      Uint8List.fromList([0x12, 0x05, 0x01]),
    ]), ['Channel 0 • Primary • (default)', 'Channel 2 • Disabled • After']);
  });

  test('manual modem mode does not claim a default preset is active', () {
    final config = Config(lora: Config_LoRaConfig(
      bandwidth: 250, spreadFactor: 11, codingRate: 5,
      region: Config_LoRaConfig_RegionCode.US, hopLimit: 3));
    expect(BastionRadioConfigCodec.loraSummary(config.writeToBuffer()),
        'Region: US • Manual modem: 250 kHz • SF 11 • Coding rate: 5 • Hop limit: 3');
  });

  test('omitted index and disabled role use protocol zero defaults', () {
    final primary = Uint8List.fromList([0x12, 0x00, 0x18, 0x01]);
    expect(BastionRadioConfigCodec.channelMetadata(primary),
        (index: 0, role: 1, name: ''));
    expect(BastionRadioConfigCodec.channelSummary(primary),
        'Channel 0 • Primary • (default)');
    final disabled = Uint8List.fromList([0x08, 0x07]);
    expect(BastionRadioConfigCodec.channelMetadata(disabled),
        (index: 7, role: 0, name: ''));
  });

  test('unknown channel roles remain invalid', () {
    expect(() => BastionRadioConfigCodec.channelMetadata(
      Uint8List.fromList([0x08, 0x01, 0x18, 0x09])), throwsFormatException);
  });

  test('reads channel name and role without exposing PSK', () {
    // Channel.index (1), settings (2), role (3); settings.psk (2), name (3).
    final channel = Uint8List.fromList([
      0x08, 0x00, 0x12, 0x0b, 0x12, 0x03, 0x01, 0x02, 0x03,
      0x1a, 0x04, 0x54, 0x45, 0x53, 0x54, 0x18, 0x01,
    ]);
    expect(BastionRadioConfigCodec.channelSummary(channel),
        'Channel 0 • Primary • TEST');
  });

  test('decodes safe channel metadata without returning a PSK', () {
    final channel = Uint8List.fromList([
      0x08, 0x01, 0x12, 0x0b, 0x12, 0x03, 0x01, 0x02, 0x03,
      0x1a, 0x04, 0x54, 0x45, 0x53, 0x54, 0x18, 0x02,
    ]);
    final metadata = BastionRadioConfigCodec.channelMetadata(channel);
    expect(metadata.index, 1);
    expect(metadata.role, 2);
    expect(metadata.name, 'TEST');
  });

  test('rejects channel metadata with invalid slot', () {
    final channel = Uint8List.fromList([
      0x08, 0x09, 0x12, 0x00, 0x18, 0x02,
    ]);
    expect(() => BastionRadioConfigCodec.channelMetadata(channel),
        throwsFormatException);
  });

  test('wrong wire types do not become default enum or slot values', () {
    expect(() => BastionRadioConfigCodec.loraSummary(
      Uint8List.fromList([0x32, 0x02, 0x3a, 0x00])), throwsFormatException);
    expect(() => BastionRadioConfigCodec.channelMetadata(
      Uint8List.fromList([0x0a, 0x00, 0x18, 0x01])), throwsFormatException);
  });

  test('rejects truncated protobuf', () {
    expect(() => BastionRadioConfigCodec.fields(Uint8List.fromList([0x12, 0x05, 0x01])),
        throwsFormatException);
  });
}
