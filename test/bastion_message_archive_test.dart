import 'dart:async';
import 'dart:convert';

import 'package:bastion/services/bastion_chat_message.dart';
import 'package:bastion/services/bastion_background_service.dart';
import 'package:bastion/services/bastion_message_archive.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// In-memory store whose reads/writes can be made to fail or stall.
final class FlakyStore extends InMemorySharedPreferencesAsync {
  FlakyStore() : super.empty();
  bool failReads = false;
  bool failWrites = false;
  Set<String> failWriteKeys = {};
  Completer<void>? readGate;
  final writes = <String>[];

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async {
    await readGate?.future;
    if (failReads) throw StateError('read failed');
    return super.getString(key, options);
  }

  @override
  Future<bool> setString(String key, String value, SharedPreferencesOptions options) async {
    if (failWrites || failWriteKeys.contains(key)) throw StateError('disk full');
    writes.add(key);
    return super.setString(key, value, options);
  }
}

BastionChatMessage msg(int id, String text) => BastionChatMessage(
  packetId: id, from: 1, to: 0xffffffff, channel: 0, text: text,
  timestamp: DateTime.utc(2026, 10, 21, 12), direction: BastionMessageDirection.incoming,
  deliveryState: BastionDeliveryState.delivered,
);

void main() {
  late FlakyStore store;
  late BastionMessageArchive archive;
  late SharedPreferencesAsync prefs;

  setUp(() {
    store = FlakyStore();
    SharedPreferencesAsyncPlatform.instance = store;
    prefs = SharedPreferencesAsync();
    archive = BastionMessageArchive();
  });

  Future<String?> stored([String key = BastionMessageArchive.key]) => prefs.getString(key);

  test('round-trips history and the offline queue with no problem', () async {
    expect(await archive.save(messages: [msg(1, 'hi')],
      pending: [const PendingTextMessage(text: 'q', destination: 5, channel: 1, packetId: 9)]), isTrue);
    final snapshot = await BastionMessageArchive().load();
    expect(snapshot.messages.single.text, 'hi');
    expect(snapshot.pending.single.packetId, 9);
    expect(archive.problem, isNull);
  });

  test('unreadable storage blocks saves so stored history is not overwritten', () async {
    await prefs.setString(BastionMessageArchive.key, jsonEncode({'messages': [msg(1, 'keep').toJson()]}));
    store.failReads = true;
    final snapshot = await archive.load();
    expect(snapshot.messages, isEmpty);
    expect(archive.problem, contains('could not be read'));
    store.failReads = false;

    expect(await archive.save(messages: [msg(2, 'new')], pending: []), isFalse);
    expect(jsonDecode((await stored())!)['messages'].single['text'], 'keep');
  });

  test('damaged JSON is backed up before history is replaced', () async {
    await prefs.setString(BastionMessageArchive.key, '{not json');
    expect((await archive.load()).messages, isEmpty);
    expect(archive.problem, contains('damaged'));
    expect(await stored(BastionMessageArchive.backupKey), '{not json');

    expect(await archive.save(messages: [msg(2, 'new')], pending: []), isTrue);
    expect(await stored(BastionMessageArchive.backupKey), '{not json');
  });

  test('one bad entry is skipped instead of losing all history', () async {
    final raw = jsonEncode({
      'messages': [msg(1, 'a').toJson(), {'text': 'broken'}, msg(3, 'c').toJson()],
      'pending': [],
    });
    await prefs.setString(BastionMessageArchive.key, raw);
    final snapshot = await archive.load();
    expect(snapshot.messages.map((m) => m.text), ['a', 'c']);
    expect(archive.problem, contains('1 saved message could not be read'));
    expect(await stored(BastionMessageArchive.backupKey), raw);
  });

  test('if damaged data cannot be backed up, saving stays off', () async {
    await prefs.setString(BastionMessageArchive.key, '[]');
    store.failWriteKeys = {BastionMessageArchive.backupKey};
    await archive.load();
    expect(archive.problem, contains('not saved'));
    expect(await archive.save(messages: [msg(2, 'new')], pending: []), isFalse);
    expect(await stored(), '[]');
  });

  test('a failed save is reported and cleared by the next good save', () async {
    var notified = 0;
    archive.addListener(() => notified++);
    store.failWrites = true;
    expect(await archive.save(messages: [msg(1, 'a')], pending: []), isFalse);
    expect(archive.problem, contains('could not be saved'));
    store.failWrites = false;
    expect(await archive.save(messages: [msg(1, 'a')], pending: []), isTrue);
    expect(archive.problem, isNull);
    expect(notified, 2);
  });

  test('saves wait for a load in progress and land in call order', () async {
    await prefs.setString(BastionMessageArchive.key, jsonEncode({'messages': [msg(1, 'old').toJson()]}));
    store.writes.clear();
    store.readGate = Completer();
    final loading = archive.load();
    final first = archive.save(messages: [msg(2, 'first')], pending: []);
    final second = archive.save(messages: [msg(3, 'second')], pending: []);
    await pumpEventQueue();
    expect(store.writes, isEmpty, reason: 'no write before the load finishes');
    store.readGate!.complete();
    expect((await loading).messages.single.text, 'old');
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(jsonDecode((await stored())!)['messages'].single['text'], 'second');
  });

  test('queueing offline during startup keeps history that is still loading', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await prefs.setString(BastionMessageArchive.key, jsonEncode({'messages': [msg(1, 'old').toJson()]}));
    store.readGate = Completer();
    final radio = MeshtasticRadioCoordinator(background: _NoopKeeper());
    final sending = radio.sendText(text: 'queued early');
    await pumpEventQueue();
    store.readGate!.complete();
    await sending;
    await pumpEventQueue();
    final saved = jsonDecode((await stored())!) as Map<String, Object?>;
    expect([for (final m in saved['messages']! as List) (m as Map)['text']], ['old', 'queued early']);
    expect((saved['pending']! as List).single, containsPair('text', 'queued early'));
    radio.dispose();
  });
}

class _NoopKeeper implements BastionBackgroundKeeper {
  @override
  Future<void> keepAlive({required String radioName, required bool reconnecting}) async {}

  @override
  Future<void> release() async {}
}
