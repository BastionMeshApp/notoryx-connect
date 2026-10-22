import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bastion/services/bastion_background_service.dart';
import 'package:bastion/services/bastion_message_archive.dart';
import 'package:bastion/services/bastion_nodedex.dart';
import 'package:bastion/services/bastion_radio_history.dart';
import 'package:bastion/services/meshtastic_connection_controller.dart';
import 'package:bastion/services/meshtastic_messaging_service.dart';
import 'package:bastion/services/meshtastic_node_database.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:bastion/services/meshtastic_radio_session.dart';
import 'package:bastion/services/meshtastic_radio_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const radioA = 0xA1;
const radioB = 0xB2;
const broadcast = 0xffffffff;

final class FlakyStore extends InMemorySharedPreferencesAsync {
  FlakyStore() : super.empty();
  Set<String> failReads = {};
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async {
    if (failReads.contains(key)) throw StateError('read failed');
    return super.getString(key, options);
  }
}

class _Transport implements MeshtasticRadioTransport {
  final sent = <Uint8List>[];
  @override Stream<Uint8List> get fromRadio => const Stream.empty();
  @override bool get isConnected => true;
  @override Future<void> connect() async {}
  @override Future<void> disconnect() async {}
  @override Future<void> sendToRadio(Uint8List envelope) async => sent.add(envelope);
}

class _NoopKeeper implements BastionBackgroundKeeper {
  @override Future<void> keepAlive({required String radioName, required bool reconnecting}) async {}
  @override Future<void> release() async {}
}

BastionChatMessage out(int id, int from, String text, {int to = broadcast}) => BastionChatMessage(
  packetId: id, from: from, to: to, channel: 0, text: text,
  timestamp: DateTime.utc(2026, 10, 1, 0, id), direction: BastionMessageDirection.outgoing,
  deliveryState: BastionDeliveryState.sent);

BastionChatMessage inbound(int id, int to, String text) => BastionChatMessage(
  packetId: id, from: 0x77, to: to, channel: 0, text: text,
  timestamp: DateTime.utc(2026, 10, 1, 0, id), direction: BastionMessageDirection.incoming,
  deliveryState: BastionDeliveryState.delivered);

void main() {
  late FlakyStore store;
  late SharedPreferencesAsync prefs;

  setUp(() {
    store = FlakyStore();
    SharedPreferencesAsyncPlatform.instance = store;
    prefs = SharedPreferencesAsync();
  });

  Future<List<String>> textsOf(int? radio) async =>
      [for (final m in (await BastionMessageArchive(radio: radio).load()).messages) m.text];

  group('chat history', () {
    test('attributes messages to the radio that sent or received them', () {
      expect(BastionRadioHistory.attributedRadio(out(1, radioA, 'x')), radioA);
      expect(BastionRadioHistory.attributedRadio(out(1, 0, 'x')), isNull);
      expect(BastionRadioHistory.attributedRadio(inbound(1, radioB, 'dm')), radioB);
      expect(BastionRadioHistory.attributedRadio(inbound(1, broadcast, 'all')), isNull);
    });

    test('unassigned history moves to radios by attribution and is kept as a copy', () async {
      await BastionMessageArchive().save(
        messages: [out(1, radioA, 'sent by A'), inbound(2, radioB, 'dm to B'), inbound(3, broadcast, 'channel chat')],
        pending: [const PendingTextMessage(text: 'queued', destination: broadcast, channel: 0, packetId: 9)]);
      final raw = await prefs.getString(BastionMessageArchive.key);

      final archive = await BastionRadioHistory().open(radioA);
      expect(archive.radio, radioA);
      expect(await textsOf(radioA), ['sent by A', 'channel chat']);
      expect((await BastionMessageArchive(radio: radioA).load()).pending.single.text, 'queued');
      expect(await textsOf(radioB), ['dm to B']);
      expect(await prefs.getString(BastionMessageArchive.key), isNull);
      expect(await prefs.getString(BastionRadioHistory.migratedKey), raw);
      expect(await BastionRadioHistory().lastRadio(), radioA);
    });

    test('unassigned history is kept when a radio archive cannot be read', () async {
      await BastionMessageArchive().save(messages: [out(1, radioA, 'keep me')], pending: []);
      store.failReads = {BastionMessageArchive.radioKey(radioA)};
      await BastionRadioHistory().open(radioA);
      store.failReads = {};
      expect(await textsOf(null), ['keep me']);
      expect(await prefs.getString(BastionRadioHistory.migratedKey), isNull);
    });

    test('merging never duplicates a message', () {
      final merged = BastionRadioHistory.mergeMessages(
        [out(1, radioA, 'a'), out(2, radioA, 'b')], [out(2, radioA, 'b'), out(3, radioA, 'c')]);
      expect([for (final m in merged) m.text], ['a', 'b', 'c']);
    });

    test('attaching a radio merges its history with messages received before', () async {
      await BastionMessageArchive(radio: radioA).save(
        messages: [out(1, radioA, 'stored')],
        pending: [const PendingTextMessage(text: 'stored queue', destination: broadcast, channel: 0, packetId: 5)]);
      final transport = _Transport();
      final connection = MeshtasticConnectionController();
      final session = MeshtasticRadioSession(transport: transport, connection: connection);
      final messaging = MeshtasticMessagingService(session: session, connection: connection, packetIdFactory: () => 77);
      await messaging.start();
      await messaging.sendText(text: 'before identify');
      expect(messaging.archive, isNull);

      await messaging.attachArchive(BastionMessageArchive(radio: radioA));
      expect([for (final m in messaging.messages) m.text], ['stored', 'before identify']);
      expect([for (final p in messaging.pending) p.packetId], [5, 77]);
      await pumpEventQueue();
      expect(await textsOf(radioA), ['stored', 'before identify']);
      await messaging.dispose();
    });

    test('offline, the coordinator shows and queues to the last radio', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await prefs.setInt(BastionRadioHistory.lastRadioKey, radioB);
      await BastionMessageArchive(radio: radioB).save(messages: [out(1, radioB, 'B history')], pending: []);
      await BastionMessageArchive(radio: radioA).save(messages: [out(1, radioA, 'A history')], pending: []);

      final radio = MeshtasticRadioCoordinator(background: _NoopKeeper());
      await radio.sendText(text: 'queued for B');
      await pumpEventQueue();
      expect([for (final m in radio.messages) m.text], ['B history', 'queued for B']);
      expect(radio.pendingMessageCount, 1);
      expect((await BastionMessageArchive(radio: radioB).load()).pending.single.text, 'queued for B');
      expect(await textsOf(radioA), ['A history']);
      radio.dispose();
    });
  });

  group('NodeDex', () {
    MeshtasticNode node(int num, String name) => MeshtasticNode(num: num, longName: name);

    test('encounters are per radio; favorites and notes are shared', () async {
      final dex = BastionNodeDex();
      await dex.useRadio(radioA);
      await dex.observe(node(7, 'Ridge'));
      await dex.setFavorite(7, true);
      await dex.setNote(7, 'solar repeater');

      await dex.useRadio(radioB);
      expect(dex.records, isEmpty, reason: 'B never heard node 7');
      await dex.observe(node(7, 'Ridge'));
      expect(dex.records.single.favorite, isTrue);
      expect(dex.records.single.note, 'solar repeater');
      expect(dex.records.single.encounters, 1);

      final reloaded = BastionNodeDex();
      await reloaded.useRadio(radioA);
      expect(reloaded.records.single.encounters, 1);
      expect(reloaded.records.single.favorite, isTrue);
    });

    test('pre-split NodeDex moves to the first radio, keeping favorites', () async {
      final now = DateTime.utc(2026, 10, 1).toIso8601String();
      final legacy = jsonEncode([
        {'num': 7, 'longName': 'Ridge', 'firstSeen': now, 'lastSeen': now, 'encounters': 4, 'favorite': true, 'note': 'gate'},
        {'num': 8, 'firstSeen': now, 'lastSeen': now, 'encounters': 1},
      ]);
      await prefs.setString(BastionNodeDex.legacyKey, legacy);
      final dex = BastionNodeDex();
      await dex.useRadio(radioA);
      expect(dex.records.map((r) => r.num), [7, 8]);
      expect(dex.records.first.note, 'gate');
      expect(dex.records.first.encounters, 4);
      expect(await prefs.getString(BastionNodeDex.legacyKey), isNull);
      expect(await prefs.getString('${BastionNodeDex.legacyKey}.migrated'), legacy);
    });

    test('nodes heard before the radio identifies itself are kept for it', () async {
      final dex = BastionNodeDex();
      await dex.useRadio(radioA);
      dex.detach();
      await dex.observe(node(9, 'Early'));
      await dex.useRadio(radioB);
      expect(dex.records.single.num, 9);
      final reloaded = BastionNodeDex();
      await reloaded.useRadio(radioB);
      expect(reloaded.records.single.longName, 'Early');
    });

    test('unreadable radio NodeDex is never overwritten', () async {
      final now = DateTime.utc(2026, 10, 1).toIso8601String();
      final stored = jsonEncode([{'num': 7, 'firstSeen': now, 'lastSeen': now, 'encounters': 3}]);
      await prefs.setString(BastionNodeDex.radioKey(radioA), stored);
      store.failReads = {BastionNodeDex.radioKey(radioA)};
      final dex = BastionNodeDex();
      await dex.useRadio(radioA);
      await dex.observe(node(8, 'New'));
      store.failReads = {};
      expect(await prefs.getString(BastionNodeDex.radioKey(radioA)), stored);
    });
  });
}
