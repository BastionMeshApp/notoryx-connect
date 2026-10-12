import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';
import '../generated/meshtastic/channel.pb.dart';
import '../generated/meshtastic/config.pb.dart';

/// Read-only views of the Meshtastic Config and Channel protobuf payloads.
/// Unknown fields are skipped, and no private channel PSKs are exposed.
abstract final class BastionRadioConfigCodec {
  static Map<int, Object> fields(Uint8List data) {
    final result = <int, Object>{};
    var offset = 0;
    int varint() {
      var value = 0;
      var shift = 0;
      while (offset < data.length && shift < 70) {
        final b = data[offset++];
        value |= (b & 127) << shift;
        if (b < 128) return value;
        shift += 7;
      }
      throw const FormatException('Invalid protobuf varint');
    }
    while (offset < data.length) {
      final key = varint();
      final number = key >> 3;
      if (number == 0) throw const FormatException('Invalid protobuf tag');
      switch (key & 7) {
        case 0:
          result[number] = varint();
        case 2:
          final length = varint();
          if (length > data.length - offset) {
            throw const FormatException('Truncated protobuf payload');
          }
          result[number] = Uint8List.sublistView(data, offset, offset + length);
          offset += length;
        case 1:
          if (offset + 8 > data.length) throw const FormatException('Truncated fixed64');
          offset += 8;
        case 5:
          if (offset + 4 > data.length) throw const FormatException('Truncated fixed32');
          offset += 4;
        default:
          throw FormatException('Unsupported protobuf wire type ${key & 7}');
      }
    }
    return result;
  }

  static String? loraSummary(Uint8List config) {
    try {
      final message = Config.fromBuffer(config);
      if (!message.hasLora()) return null;
      final lora = message.lora;
      final values = fields(lora.writeToBuffer());
      final regionValue = values[7] as int? ?? lora.region.value;
      final presetValue = values[2] as int? ?? lora.modemPreset.value;
      final region = Config_LoRaConfig_RegionCode.valueOf(regionValue)?.name
          ?? 'Unknown ($regionValue)';
      final preset = Config_LoRaConfig_ModemPreset.valueOf(presetValue)?.name;
      final modem = lora.usePreset
          ? 'Preset: ${preset == null ? 'Unknown ($presetValue)' : _enumLabel(preset)}'
          : 'Manual modem: ${lora.bandwidth} kHz • SF ${lora.spreadFactor} • Coding rate: ${lora.codingRate}';
      return 'Region: $region • $modem • Hop limit: ${lora.hopLimit}';
    } on InvalidProtocolBufferException {
      throw const FormatException('Invalid LoRa configuration');
    }
  }

  /// Decode protocol defaults without exposing private channel keys.
  static ({int index, int role, String name}) channelMetadata(Uint8List bytes) {
    try {
      final channel = Channel.fromBuffer(bytes);
      // Check the raw enum too: generated readers preserve unknown enum values
      // as unknown fields and expose the default through the getter.
      final role = fields(bytes)[3] ?? channel.role.value;
      if (channel.index < 0 || channel.index > 7 ||
          role is! int || role < 0 || role > 2) {
        throw const FormatException('Invalid channel metadata');
      }
      return (index: channel.index, role: role, name: channel.settings.name);
    } on InvalidProtocolBufferException {
      throw const FormatException('Invalid channel metadata');
    }
  }

  static String channelSummary(Uint8List channel) {
    final metadata = channelMetadata(channel);
    final role = switch (metadata.role) {
      1 => 'Primary', 2 => 'Secondary', _ => 'Disabled',
    };
    return 'Channel ${metadata.index} • $role • ${metadata.name.isEmpty ? '(default)' : metadata.name}';
  }

  /// Latest valid summary per channel slot, ordered by the protocol index.
  static List<String> channelSummaries(Iterable<Uint8List> snapshots) {
    final bySlot = <int, String>{};
    for (final payload in snapshots) {
      try {
        bySlot[channelMetadata(payload).index] = channelSummary(payload);
      } on FormatException {
        // A bad frame must not replace the latest valid settings.
      }
    }
    final slots = bySlot.keys.toList()..sort();
    return List.unmodifiable(slots.map((slot) => bySlot[slot]!));
  }

  static String _enumLabel(String name) => name.split('_')
      .map((word) => word.isEmpty ? word : word[0] + word.substring(1).toLowerCase())
      .join(' ');
}
