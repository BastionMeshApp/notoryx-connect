import 'package:bastion/main.dart';
import 'package:bastion/services/bastion_field_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const me = 0x10;
const fav = 0x20;
const other = 0x30;

void main() {
  late DateTime now;
  late BastionFieldAlertEngine engine;
  const on = BastionAlertSettings(lowBattery: true, newNode: true, favoriteSilent: true,
      batteryThreshold: 20, silence: Duration(hours: 1));

  setUp(() {
    now = DateTime.utc(2026, 10, 21, 12);
    engine = BastionFieldAlertEngine(clock: () => now)..startSession(me);
  });

  BastionFieldAlert? battery(int node, int? level, {bool favorite = false, BastionAlertSettings s = on}) =>
      engine.battery(node, level, 'Node', favorite: favorite, settings: s);

  group('low battery', () {
    test('alerts once for your radio, then rearms only after recovering', () {
      expect(battery(me, 25), isNull);
      expect(battery(me, 20)?.title, 'Your radio battery is low');
      expect(battery(me, 15), isNull, reason: 'already alerted');
      expect(battery(me, 23), isNull, reason: 'inside the hysteresis band');
      expect(battery(me, 19), isNull, reason: 'not yet recovered');
      expect(battery(me, 26), isNull);
      expect(battery(me, 18), isNotNull, reason: 'recovered above 25%, so rearmed');
    });

    test('only your radio and favorites alert; unknown and external power never do', () {
      expect(battery(other, 5), isNull);
      expect(battery(fav, 5, favorite: true)?.body, 'Node reports 5% battery.');
      expect(battery(me, null), isNull);
      expect(battery(me, 101), isNull, reason: '101 means external power');
      expect(battery(me, 5, s: on.copyWith(lowBattery: false)), isNull);
    });
  });

  group('new node', () {
    test('alerts for a node first heard live, once', () {
      expect(engine.nodeHeard(other, 'Ridge', knownBefore: false, settings: on)?.title, 'New node: Ridge');
      expect(engine.nodeHeard(other, 'Ridge', knownBefore: false, settings: on), isNull);
      expect(engine.nodeHeard(fav, 'Camp', knownBefore: true, settings: on), isNull);
      expect(engine.nodeHeard(me, 'Me', knownBefore: false, settings: on), isNull);
      expect(engine.nodeHeard(0x40, 'X', knownBefore: false, settings: on.copyWith(newNode: false)), isNull);
    });
  });

  group('favorite goes quiet', () {
    ({int num, String name, DateTime? lastHeard}) f(DateTime? heard) => (num: fav, name: 'Camp', lastHeard: heard);

    test('counts from session start, not from before connecting', () {
      final longAgo = now.subtract(const Duration(days: 3));
      expect(engine.checkSilence([f(longAgo)], on), isEmpty, reason: 'just connected');
      now = now.add(const Duration(minutes: 59));
      expect(engine.checkSilence([f(longAgo)], on), isEmpty);
      now = now.add(const Duration(minutes: 1));
      expect(engine.checkSilence([f(longAgo)], on).single.body, 'Not heard for 1 h 0 min.');
      now = now.add(const Duration(minutes: 30));
      expect(engine.checkSilence([f(longAgo)], on), isEmpty, reason: 'alerts once');
    });

    test('rearms after the favorite is heard again', () {
      now = now.add(const Duration(hours: 2));
      expect(engine.checkSilence([f(null)], on), hasLength(1));
      final heard = now;
      expect(engine.checkSilence([f(heard)], on), isEmpty);
      now = now.add(const Duration(hours: 1));
      expect(engine.checkSilence([f(heard)], on), hasLength(1));
    });
  });

  test('nothing alerts outside a connected session', () {
    engine.endSession();
    expect(battery(me, 1), isNull);
    expect(engine.nodeHeard(other, 'Ridge', knownBefore: false, settings: on), isNull);
    now = now.add(const Duration(days: 1));
    expect(engine.checkSilence([(num: fav, name: 'Camp', lastHeard: null)], on), isEmpty);
  });

  test('settings round-trip and fall back to defaults on bad values', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    expect(await BastionAlertSettings.load(), const BastionAlertSettings());
    final custom = on.copyWith(batteryThreshold: 30, silence: const Duration(hours: 6));
    expect(await custom.save(), isTrue);
    expect(await BastionAlertSettings.load(), custom);
    expect(BastionAlertSettings.fromJson({'batteryThreshold': 7, 'silenceMinutes': 5, 'newNode': 'yes'}),
        const BastionAlertSettings());
  });

  testWidgets('Settings shows field alerts and saves a change', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await tester.pumpWidget(const BastionApp());
    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Field alerts'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Field alerts'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('New node'), 100, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('New node'));
    await tester.pumpAndSettle();
    expect((await BastionAlertSettings.load()).newNode, isTrue);
  });
}
