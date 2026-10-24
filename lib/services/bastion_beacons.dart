import 'dart:convert';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/meshtastic/apponly.pb.dart';
import '../generated/meshtastic/channel.pb.dart';
import '../generated/meshtastic/config.pbenum.dart';
import '../generated/meshtastic/mesh.pb.dart' as pb;
import '../generated/meshtastic/mesh_beacon.pb.dart';
import '../generated/meshtastic/portnums.pbenum.dart';
import 'meshtastic_channel_url.dart';
import 'meshtastic_text_codec.dart';

/// A Mesh Beacon heard on the mesh: a short message, optionally inviting
/// listeners to a channel, region and modem preset.
class HeardBeacon {
  const HeardBeacon({
    required this.from,
    required this.heardAt,
    required this.message,
    this.offerChannel,
    this.offerRegion,
    this.offerPreset,
    this.offerFrequencySlot,
    this.snr,
    this.rssi,
  });

  final int from;
  final DateTime heardAt;
  final String message;

  /// The channel (name and key) the beacon invites listeners to, if any.
  final ChannelSettings? offerChannel;
  final Config_LoRaConfig_RegionCode? offerRegion;
  final Config_LoRaConfig_ModemPreset? offerPreset;
  final int? offerFrequencySlot;
  final double? snr;
  final int? rssi;

  /// The offered channel as an add-only channel link, for the channel import
  /// screen; null when the beacon offers no channel.
  String? get joinLink => offerChannel == null
      ? null
      // The official add link puts `?add=true` before the fragment.
      : MeshtasticChannelUrl.encode(ChannelSet(settings: [offerChannel!]))
          .replaceFirst('/e/#', '/e/?add=true#');

  /// Whether two beacons carry the same content from the same node.
  bool sameAs(HeardBeacon other) =>
      from == other.from &&
      message == other.message &&
      offerRegion == other.offerRegion &&
      offerPreset == other.offerPreset &&
      offerFrequencySlot == other.offerFrequencySlot &&
      (offerChannel?.writeToBuffer().join(',') ?? '') ==
          (other.offerChannel?.writeToBuffer().join(',') ?? '');

  Map<String, Object?> toJson() => {
        'from': from,
        'at': heardAt.millisecondsSinceEpoch,
        'message': message,
        'channel': offerChannel == null ? null : base64Encode(offerChannel!.writeToBuffer()),
        'region': offerRegion?.value,
        'preset': offerPreset?.value,
        'slot': offerFrequencySlot,
        'snr': snr,
        'rssi': rssi,
      };

  static HeardBeacon fromJson(Map<String, Object?> json) => HeardBeacon(
        from: json['from']! as int,
        heardAt: DateTime.fromMillisecondsSinceEpoch(json['at']! as int, isUtc: true),
        message: json['message'] as String? ?? '',
        offerChannel: json['channel'] == null
            ? null
            : ChannelSettings.fromBuffer(base64Decode(json['channel']! as String)),
        offerRegion: json['region'] == null
            ? null
            : Config_LoRaConfig_RegionCode.valueOf(json['region']! as int),
        offerPreset: json['preset'] == null
            ? null
            : Config_LoRaConfig_ModemPreset.valueOf(json['preset']! as int),
        offerFrequencySlot: json['slot'] as int?,
        snr: (json['snr'] as num?)?.toDouble(),
        rssi: json['rssi'] as int?,
      );
}

/// Keeps the Mesh Beacons heard on the mesh and limits how often this phone
/// sends one. Radios without the Mesh Beacon module still pass beacon packets
/// to the phone, so they can be shown here.
class BastionBeaconLog {
  BastionBeaconLog({DateTime Function()? clock, SharedPreferencesAsync? preferences})
      : _clock = clock ?? DateTime.now,
        _preferences = preferences;

  static const _key = 'bastion.beacons.v1';
  static const _sentKey = 'bastion.beacons.last_sent';

  /// The firmware's beacon message limit; every copy carries it on the air.
  static const maxMessageBytes = 60;

  /// Matches the firmware's minimum broadcast interval.
  static const sendInterval = Duration(hours: 1);

  /// How many heard beacons are kept.
  static const maxKept = 50;

  final DateTime Function() _clock;
  SharedPreferencesAsync? _preferences;
  final List<HeardBeacon> _beacons = [];
  DateTime? _lastSent;

  SharedPreferencesAsync get _store => _preferences ??= SharedPreferencesAsync();

  /// Heard beacons, newest first.
  List<HeardBeacon> get beacons => List.unmodifiable(_beacons);

  /// When this phone may send its next beacon; null when it may send now.
  DateTime? get nextSendAllowed {
    final last = _lastSent;
    if (last == null) return null;
    final next = last.add(sendInterval);
    return next.isAfter(_clock()) ? next : null;
  }

  Future<void> load() async {
    try {
      final raw = await _store.getString(_key);
      if (raw != null) {
        for (final item in jsonDecode(raw) as List<Object?>) {
          _beacons.add(HeardBeacon.fromJson((item! as Map).cast<String, Object?>()));
        }
      }
      final sent = await _store.getInt(_sentKey);
      if (sent != null) _lastSent = DateTime.fromMillisecondsSinceEpoch(sent, isUtc: true);
    } catch (_) {
      // A damaged store is ignored rather than blocking the app.
    }
  }

  Future<void> _save() async {
    try {
      await _store.setString(_key, jsonEncode([for (final b in _beacons) b.toJson()]));
    } catch (_) {
      // Persistence is best effort.
    }
  }

  /// Records a MESH_BEACON_APP packet. Returns true when the list changed.
  Future<bool> handlePacket(pb.MeshPacket packet) async {
    if (!packet.hasDecoded() || packet.decoded.portnum != PortNum.MESH_BEACON_APP) return false;
    final MeshBeacon beacon;
    try {
      beacon = MeshBeacon.fromBuffer(packet.decoded.payload);
    } on InvalidProtocolBufferException {
      return false;
    }
    final heard = HeardBeacon(
      from: packet.from,
      heardAt: _clock().toUtc(),
      message: beacon.message,
      offerChannel: beacon.hasOfferChannel() ? beacon.offerChannel : null,
      offerRegion: beacon.hasOfferRegion() ? beacon.offerRegion : null,
      offerPreset: beacon.hasOfferPreset() ? beacon.offerPreset : null,
      offerFrequencySlot: beacon.hasOfferFrequencySlot() ? beacon.offerFrequencySlot : null,
      snr: packet.hasRxSnr() ? packet.rxSnr : null,
      rssi: packet.hasRxRssi() ? packet.rxRssi : null,
    );
    // A repeat of the same beacon replaces the older copy.
    _beacons
      ..removeWhere(heard.sameAs)
      ..insert(0, heard);
    if (_beacons.length > maxKept) _beacons.removeRange(maxKept, _beacons.length);
    await _save();
    return true;
  }

  /// Remembers that a beacon was sent now, for [nextSendAllowed].
  Future<void> recordSent() async {
    _lastSent = _clock().toUtc();
    try {
      await _store.setInt(_sentKey, _lastSent!.millisecondsSinceEpoch);
    } catch (_) {
      // The limit still applies for this session.
    }
  }

  Future<void> clear() async {
    _beacons.clear();
    await _save();
  }

  /// Throws [ArgumentError] unless [message] is non-empty and fits.
  static void checkMessage(String message) {
    if (message.trim().isEmpty) throw ArgumentError('Enter a beacon message.');
    if (utf8.encode(message).length > maxMessageBytes) {
      throw ArgumentError('Beacon messages are limited to $maxMessageBytes bytes.');
    }
  }

  /// Broadcast envelope for [beacon] on [channel].
  static Uint8List encode(MeshBeacon beacon, {int channel = 0}) => pb.ToRadio(
        packet: pb.MeshPacket(
          to: MeshtasticTextCodec.broadcastNode,
          channel: channel,
          decoded: pb.Data(
            portnum: PortNum.MESH_BEACON_APP,
            payload: beacon.writeToBuffer(),
          ),
        ),
      ).writeToBuffer();
}
