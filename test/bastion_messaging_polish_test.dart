import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/meshtastic_connection_controller.dart';
import 'package:bastion/services/meshtastic_messaging_service.dart';
import 'package:bastion/services/meshtastic_radio_session.dart';
import 'package:bastion/services/meshtastic_radio_transport.dart';
import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements MeshtasticRadioTransport {
  final sent = <Uint8List>[];
  final controller = StreamController<Uint8List>.broadcast();
  bool connected = false;

  @override
  Stream<Uint8List> get fromRadio => controller.stream;
  @override
  bool get isConnected => connected;
  @override
  Future<void> connect() async => connected = true;
  @override
  Future<void> disconnect() async => connected = false;
  @override
  Future<void> sendToRadio(Uint8List envelope) async => sent.add(envelope);
}

const me = 0x10;

pb.MeshPacket textPacket(String text, {int from = 0x22, int to = me, int id = 500, int? replyId,
    bool reaction = false, bool viaMqtt = false, DateTime? at}) => pb.MeshPacket(
  from: from,
  to: to,
  id: id,
  viaMqtt: viaMqtt,
  rxTime: at == null ? null : at.millisecondsSinceEpoch ~/ 1000,
  decoded: pb.Data(
    portnum: PortNum.TEXT_MESSAGE_APP,
    payload: utf8.encode(text),
    replyId: replyId,
    emoji: reaction ? 1 : null,
  ),
);

void main() {
  group('codec', () {
    test('encodes a reaction with reply_id and the emoji flag', () {
      final bytes = MeshtasticTextCodec.toRadioText(
          text: '👍', destination: 0x22, packetId: 9, replyId: 77, reaction: true);
      final packet = pb.ToRadio.fromBuffer(bytes).packet;
      expect(utf8.decode(packet.decoded.payload), '👍');
      expect(packet.decoded.replyId, 77);
      expect(packet.decoded.emoji, 1);

      final decoded = MeshtasticTextCodec.decodeMeshPacket(packet.writeToBuffer())!;
      expect(decoded.isReaction, isTrue);
      expect(decoded.replyId, 77);
    });

    test('a plain message has no reply or reaction fields', () {
      final packet = pb.ToRadio.fromBuffer(
          MeshtasticTextCodec.toRadioText(text: 'hi', destination: 1, packetId: 3)).packet;
      expect(packet.decoded.hasReplyId(), isFalse);
      expect(packet.decoded.hasEmoji(), isFalse);
      final decoded = MeshtasticTextCodec.decodeMeshPacket(packet.writeToBuffer())!;
      expect(decoded.isReaction, isFalse);
      expect(decoded.replyId, isNull);
      expect(decoded.viaMqtt, isFalse);
    });

    test('reads via_mqtt', () {
      final decoded = MeshtasticTextCodec.decodeMeshPacket(
          textPacket('from the internet', viaMqtt: true).writeToBuffer())!;
      expect(decoded.viaMqtt, isTrue);
    });
  });

  test('chat messages keep reaction and MQTT fields when saved', () {
    final message = BastionChatMessage(packetId: 1, from: 2, to: 3, channel: 0, text: '❤️',
        timestamp: DateTime.utc(2026), direction: BastionMessageDirection.incoming,
        deliveryState: BastionDeliveryState.received, replyId: 77, isReaction: true, viaMqtt: true);
    final copy = BastionChatMessage.fromJson(jsonDecode(jsonEncode(message.toJson())) as Map<String, Object?>);
    expect(copy.replyId, 77);
    expect(copy.isReaction, isTrue);
    expect(copy.viaMqtt, isTrue);
    expect(copy.copyWith(deliveryState: BastionDeliveryState.failed).isReaction, isTrue);

    final pending = PendingTextMessage.fromJson(jsonDecode(jsonEncode(const PendingTextMessage(
        text: '👍', destination: 2, channel: 0, packetId: 5, replyId: 4, isReaction: true).toJson()))
        as Map<String, Object?>);
    expect(pending.replyId, 4);
    expect(pending.isReaction, isTrue);
  });

  group('messaging service', () {
    late _FakeTransport transport;
    late MeshtasticConnectionController connection;
    late MeshtasticMessagingService messaging;

    setUp(() async {
      transport = _FakeTransport();
      connection = MeshtasticConnectionController();
      final session = MeshtasticRadioSession(transport: transport, connection: connection);
      messaging = MeshtasticMessagingService(session: session, connection: connection, packetIdFactory: () => 42);
      await session.connect(deviceName: 'Field Radio');
      await messaging.start();
      connection.markReady();
      messaging.configureBot(enabled: true, reply: 'Away', nodeNum: me);
    });

    Future<void> receive(pb.MeshPacket packet) async {
      transport.controller.add(pb.FromRadio(packet: packet).writeToBuffer());
      await Future<void>.delayed(Duration.zero);
    }

    test('an incoming reaction is stored as a reaction and never bot-answered', () async {
      await receive(textPacket('👍', replyId: 42, reaction: true, viaMqtt: true));
      final stored = messaging.messages.single;
      expect(stored.isReaction, isTrue);
      expect(stored.replyId, 42);
      expect(stored.viaMqtt, isTrue);
      expect(transport.sent, isEmpty);
    });

    test('a reaction is sent with its reply id and the emoji flag', () async {
      await messaging.sendText(text: '✅', destination: 0x22, replyId: 7, reaction: true);
      final packet = pb.ToRadio.fromBuffer(transport.sent.single).packet;
      expect(packet.decoded.replyId, 7);
      expect(packet.decoded.emoji, 1);
      expect(messaging.messages.single.isReaction, isTrue);
    });

    test('old channel messages are deleted, direct messages kept', () async {
      final old = DateTime.now().subtract(const Duration(days: 3));
      await receive(textPacket('old channel', to: 0xffffffff, id: 1, at: old));
      await receive(textPacket('old direct', id: 2, at: old));
      await receive(textPacket('new channel', to: 0xffffffff, id: 3));
      expect(messaging.messages, hasLength(3));

      messaging
        ..channelMessageMaxAge = const Duration(days: 1)
        ..pruneChannelMessages();
      expect(messaging.messages.map((m) => m.text), ['old direct', 'new channel']);
    });
  });
}
