import 'meshtastic_text_codec.dart';

enum BastionMessageDirection { incoming, outgoing }
enum BastionDeliveryState { received, queued, sent, delivered, failed }

class BastionChatMessage {
  const BastionChatMessage({
    required this.packetId,
    required this.from,
    required this.to,
    required this.channel,
    required this.text,
    required this.timestamp,
    required this.direction,
    required this.deliveryState,
    this.rxSnr,
    this.replyId,
    this.isReaction = false,
    this.viaMqtt = false,
  });

  final int packetId;
  final int from;
  final int to;
  final int channel;
  final String text;
  final DateTime timestamp;
  final BastionMessageDirection direction;
  final BastionDeliveryState deliveryState;
  final double? rxSnr;

  /// The message this one reacts to, when [isReaction].
  final int? replyId;

  /// An emoji reaction to [replyId] rather than a message of its own.
  final bool isReaction;

  /// Reached the radio over MQTT (the internet), not over LoRa.
  final bool viaMqtt;

  bool get isBroadcast => to == MeshtasticTextCodec.broadcastNode;

  BastionChatMessage copyWith({BastionDeliveryState? deliveryState}) =>
      BastionChatMessage(
        packetId: packetId,
        from: from,
        to: to,
        channel: channel,
        text: text,
        timestamp: timestamp,
        direction: direction,
        deliveryState: deliveryState ?? this.deliveryState,
        rxSnr: rxSnr,
        replyId: replyId,
        isReaction: isReaction,
        viaMqtt: viaMqtt,
      );

  Map<String, Object?> toJson() => {
    'packetId': packetId,
    'from': from,
    'to': to,
    'channel': channel,
    'text': text,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'direction': direction.name,
    'deliveryState': deliveryState.name,
    if (rxSnr != null) 'rxSnr': rxSnr,
    if (replyId != null) 'replyId': replyId,
    if (isReaction) 'reaction': true,
    if (viaMqtt) 'viaMqtt': true,
  };

  static BastionChatMessage fromJson(Map<String, Object?> json) {
    return BastionChatMessage(
      packetId: json['packetId']! as int,
      from: json['from']! as int,
      to: json['to']! as int,
      channel: json['channel']! as int,
      text: json['text']! as String,
      timestamp: DateTime.parse(json['timestamp']! as String).toLocal(),
      direction: BastionMessageDirection.values.byName(
        json['direction']! as String,
      ),
      deliveryState: BastionDeliveryState.values.byName(
        json['deliveryState']! as String,
      ),
      rxSnr: (json['rxSnr'] as num?)?.toDouble(),
      replyId: json['replyId'] as int?,
      isReaction: json['reaction'] as bool? ?? false,
      viaMqtt: json['viaMqtt'] as bool? ?? false,
    );
  }
}

class PendingTextMessage {
  const PendingTextMessage({
    required this.text,
    required this.destination,
    required this.channel,
    required this.packetId,
    this.replyId,
    this.isReaction = false,
  });

  final String text;
  final int destination;
  final int channel;
  final int packetId;
  final int? replyId;
  final bool isReaction;

  Map<String, Object?> toJson() => {
    'text': text,
    'destination': destination,
    'channel': channel,
    'packetId': packetId,
    if (replyId != null) 'replyId': replyId,
    if (isReaction) 'reaction': true,
  };

  static PendingTextMessage fromJson(Map<String, Object?> json) =>
      PendingTextMessage(
        text: json['text']! as String,
        destination: json['destination']! as int,
        channel: json['channel']! as int,
        packetId: json['packetId']! as int,
        replyId: json['replyId'] as int?,
        isReaction: json['reaction'] as bool? ?? false,
      );
}
