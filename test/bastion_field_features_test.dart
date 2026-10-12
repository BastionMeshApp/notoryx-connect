import 'package:bastion/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion/services/bastion_bot_guard.dart';
import 'package:bastion/services/bastion_field_log.dart';
import 'package:bastion/services/bastion_phone_position.dart';
import 'package:bastion/services/bastion_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  final now = DateTime.now();
  pb.MeshPacket packet({int sender = 9, bool mqtt = false, DateTime? time}) => pb.MeshPacket(
    from: sender, id: 1, rxTime: (time ?? now).millisecondsSinceEpoch ~/ 1000, rxSnr: 0, rxRssi: -95, viaMqtt: mqtt);
  PhoneFix fix({DateTime? time, double accuracy = 10}) => PhoneFix(latitude: 35, longitude: -80, time: time ?? now, accuracyMeters: accuracy);

  test('incident notes survive reload and CSV escapes quotes, lines and formulas', () async {
    final log = BastionFieldLog();
    await log.addIncident('=1+1\n"note"', radio: 42);
    final loaded = BastionFieldLog();
    await loaded.load();
    expect(loaded.records.single['radio'], 42);
    expect(loaded.records.single['note'], '=1+1\n"note"');
    expect(loaded.exportCsv('incident'), contains('"\'=1+1\n""note"""'));
    expect(loaded.exportCsv('coverage'), isNot(contains('note""')));
  });

  test('coverage needs opt-in, accurate fresh receiver GPS and fresh RF', () async {
    final log = BastionFieldLog();
    await log.observe(packet(), fix(), now);
    expect(log.records, isEmpty);
    log.start(42);
    await log.observe(packet(mqtt: true), fix(), now);
    await log.observe(packet(sender: 42), fix(), now);
    await log.observe(packet(), fix(accuracy: 100), now);
    await log.observe(packet(), fix(time: now.subtract(const Duration(minutes: 1))), now);
    await log.observe(packet(time: now.subtract(const Duration(minutes: 3))), fix(), now);
    await log.observe(packet(time: now.add(const Duration(seconds: 5))), fix(), now);
    expect(log.records, isEmpty);
    await log.observe(packet(), fix(), now);
    await log.observe(packet(), fix(), now);
    expect(log.records, hasLength(1));
    expect(log.records.single['snr'], 0); // Zero is a valid signal measurement.
    final loaded = BastionFieldLog(); await loaded.load();
    expect(loaded.records.single['lat'], 35);
    expect(loaded.recording, isFalse);
    log.stop(); await log.observe(packet(sender: 11), fix(), now);
    expect(log.records, hasLength(1));
  });

  test('bot quiet hours handle midnight and full-day intervals', () {
    final guard = BastionBotGuard();
    expect(guard.isQuiet(DateTime(2026, 1, 1, 23)), isTrue);
    expect(guard.isQuiet(DateTime(2026, 1, 1, 6)), isTrue);
    expect(guard.isQuiet(DateTime(2026, 1, 1, 7)), isFalse);
    guard.quietStart = 8; guard.quietEnd = 17;
    expect(guard.isQuiet(DateTime(2026, 1, 1, 12)), isTrue);
    expect(guard.isQuiet(DateTime(2026, 1, 1, 20)), isFalse);
    guard.quietEnd = 8;
    expect(guard.isQuiet(DateTime(2026, 1, 1, 20)), isTrue);
  });

  test('bot reserves persisted hourly and sender budgets before sends', () async {
    final guard = BastionBotGuard(); await guard.update(quiet: false);
    Future<bool> reserve(BastionBotGuard g, int sender, DateTime time, {int channel = 0, int? rx}) =>
      g.reserve(sender: sender, receivedChannel: channel, rxTime: rx ?? time.millisecondsSinceEpoch ~/ 1000, now: time);
    expect(await reserve(guard, 1, now, channel: 1), isFalse);
    expect(await reserve(guard, 0, now), isFalse);
    expect(await reserve(guard, 1, now, rx: now.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch ~/ 1000), isFalse);
    expect(await reserve(guard, 1, now), isTrue);
    final restarted = BastionBotGuard();
    expect(await reserve(restarted, 2, now), isFalse); // Global spacing survives restart.
    expect(await reserve(restarted, 1, now.add(const Duration(minutes: 1))), isFalse);
    for (var n = 2; n <= 6; n++) {
      expect(await reserve(restarted, n, now.add(Duration(minutes: n))), isTrue);
    }
    expect(await reserve(restarted, 7, now.add(const Duration(minutes: 7))), isFalse);
    expect(await reserve(restarted, 7, now.add(const Duration(hours: 1, minutes: 1))), isTrue);
  });

  test('theme and dashboard choices persist while dark stays the initial default', () async {
    final prefs = BastionPreferences(); expect(prefs.theme, ThemeMode.dark);
    await prefs.update(mode: ThemeMode.system, stats: false, saved: false);
    final loaded = BastionPreferences(); await loaded.load();
    expect(loaded.theme, ThemeMode.system);
    expect(loaded.statistics, isFalse); expect(loaded.encounters, isFalse); expect(loaded.meshHealth, isTrue);
  });
}
