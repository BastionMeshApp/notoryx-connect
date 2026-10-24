import 'package:bastion/services/bastion_chat_message.dart';
import 'package:bastion/services/bastion_field_alerts.dart';
import 'package:bastion/services/bastion_trip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const me = 0x10;
const alice = 0xa1;
const bob = 0xb2;

class FakeRadio implements TripRadio {
  @override
  bool isReady = true;
  @override
  int? localNodeNum = me;
  @override
  ({double? latitude, double? longitude, int? battery}) localStatus =
      (latitude: 35.12345, longitude: -83.5, battery: 80);
  @override
  final List<BastionChatMessage> messages = [];
  final Map<int, DateTime> heard = {};
  final List<({String text, int destination, int channel})> sent = [];
  final List<BastionFieldAlert> alerts = [];
  final Set<int> failTo = {};
  var _id = 1000;

  @override
  DateTime? lastHeard(int node) => heard[node];
  @override
  String nodeName(int node) => switch (node) { alice => 'Alice', bob => 'Bob', _ => '!$node' };
  @override
  void alert(BastionFieldAlert alert) => alerts.add(alert);

  @override
  Future<int> sendText({required String text, required int destination, required int channel}) async {
    if (failTo.contains(destination)) throw StateError('queue full');
    sent.add((text: text, destination: destination, channel: channel));
    final id = _id++;
    messages.add(BastionChatMessage(packetId: id, from: me, to: destination, channel: channel, text: text,
        timestamp: DateTime.utc(2026), direction: BastionMessageDirection.outgoing,
        deliveryState: BastionDeliveryState.sent));
    return id;
  }

  void setState(int packetId, BastionDeliveryState state) {
    final i = messages.indexWhere((m) => m.packetId == packetId);
    messages[i] = messages[i].copyWith(deliveryState: state);
  }
}

void main() {
  late FakeRadio radio;
  late DateTime now;
  late BastionTripController trip;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    radio = FakeRadio();
    now = DateTime.utc(2026, 10, 24, 9);
    trip = BastionTripController(radio: radio, clock: () => now);
    await trip.load();
  });
  tearDown(() => trip.dispose());

  group('messages', () {
    test('check-in carries label, UTC time, position and battery', () {
      expect(checkInText("I'm OK", DateTime.utc(2026, 10, 24, 9, 5), latitude: 35.1, longitude: -83.2, battery: 80),
          "[NOTORYX Check-in] I'm OK | 2026-10-24 09:05 UTC | Pos 35.10000,-83.20000 | Battery 80%");
    });

    test('external power and missing positions are left out of a check-in', () {
      expect(checkInText('At camp', DateTime.utc(2026), latitude: 0, longitude: 0, battery: 101),
          '[NOTORYX Check-in] At camp | 2026-01-01 00:00 UTC');
    });

    test('SOS always says whether a position is included', () {
      expect(sosText(DateTime.utc(2026)), '[NOTORYX SOS] Need help | 2026-01-01 00:00 UTC | No position');
      expect(sosAllClearText(DateTime.utc(2026)), '[NOTORYX SOS] All clear | 2026-01-01 00:00 UTC');
    });
  });

  test('a check-in goes to every trip contact and tracks delivery', () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice, bob]));
    await trip.checkIn("I'm OK");
    expect(radio.sent.map((s) => s.destination), [alice, bob]);
    expect(radio.sent.first.text, startsWith("[NOTORYX Check-in] I'm OK"));
    final record = trip.lastCheckIn!;
    radio.setState(record.packets[alice]!, BastionDeliveryState.delivered);
    radio.setState(record.packets[bob]!, BastionDeliveryState.failed);
    expect(trip.delivery(record), {alice: BastionDeliveryState.delivered, bob: BastionDeliveryState.failed});

    await trip.resendFailed();
    expect(radio.sent.last.destination, bob);
    expect(trip.delivery(trip.lastCheckIn!)[bob], BastionDeliveryState.sent);
    expect(trip.checkIns, hasLength(1));
  });

  test('check-in needs a radio and trip contacts', () async {
    expect(trip.checkInBlocked, 'Choose trip contacts first.');
    await trip.updatePlan(trip.plan.copyWith(members: [alice]));
    radio.isReady = false;
    expect(() => trip.checkIn("I'm OK"), throwsStateError);
  });

  test('a contact that cannot be queued is reported, others still get it', () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice, bob]));
    radio.failTo.add(alice);
    await trip.checkIn('Delayed');
    expect(radio.sent.map((s) => s.destination), [bob]);
    expect(trip.problem, contains('queue full'));
  });

  test('SOS repeats every 5 minutes up to the limit', () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice], sosChannel: 2));
    await trip.startSos();
    expect(radio.sent.map((s) => (s.destination, s.channel)), [(alice, 0), (0xffffffff, 2)]);
    expect(radio.sent.first.text, contains('Pos 35.12345,-83.50000'));

    now = now.add(const Duration(minutes: 4));
    await trip.tick();
    expect(trip.sos.sends, 1);
    for (var i = 0; i < 20; i++) {
      now = now.add(sosRepeatInterval);
      await trip.tick();
    }
    expect(trip.sos.sends, sosMaxSends);
    expect(trip.sos.nextSendAt, isNull);
    expect(trip.sos.active, isTrue);
  });

  test('a reply from a trip contact acknowledges the SOS and stops repeats', () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice]));
    await trip.startSos();
    radio.messages.add(BastionChatMessage(packetId: 1, from: alice, to: me, channel: 0, text: 'On my way',
        timestamp: now.add(const Duration(minutes: 1)), direction: BastionMessageDirection.incoming,
        deliveryState: BastionDeliveryState.received));
    now = now.add(const Duration(minutes: 6));
    await trip.tick();
    expect(trip.sos.acknowledgedBy, 'Alice');
    expect(trip.sos.sends, 1);
    expect(radio.alerts.single.kind, BastionAlertKind.sosAcknowledged);
  });

  test("I'm safe sends one all-clear and ends the SOS", () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice]));
    await trip.startSos();
    await trip.stopSos(allClear: true);
    expect(trip.sos.active, isFalse);
    expect(radio.sent.last.text, startsWith('[NOTORYX SOS] All clear'));
    now = now.add(const Duration(minutes: 10));
    await trip.tick();
    expect(radio.sent, hasLength(2));
  });

  test('SOS without contacts or channel is refused', () {
    expect(trip.sosBlocked, isNotNull);
    expect(trip.startSos, throwsStateError);
  });

  test('reminder fires once after the interval and rearms on check-in', () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice], reminderMinutes: 30, overdueMinutes: 0));
    await trip.startTrip();
    now = now.add(const Duration(minutes: 29));
    await trip.tick();
    expect(radio.alerts, isEmpty);
    now = now.add(const Duration(minutes: 2));
    await trip.tick();
    await trip.tick();
    expect(radio.alerts.map((a) => a.kind), [BastionAlertKind.checkInDue]);
    await trip.checkIn("I'm OK");
    now = now.add(const Duration(minutes: 31));
    await trip.tick();
    expect(radio.alerts.map((a) => a.kind), [BastionAlertKind.checkInDue, BastionAlertKind.checkInDue]);
  });

  test('overdue contacts alert once and rearm when heard again', () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice, bob], overdueMinutes: 60));
    await trip.startTrip();
    radio.heard[bob] = now.add(const Duration(minutes: 30));
    now = now.add(const Duration(minutes: 61));
    await trip.tick();
    await trip.tick();
    expect(trip.overdue, [alice]);
    expect(radio.alerts.map((a) => (a.kind, a.nodeNum)), [(BastionAlertKind.contactOverdue, alice)]);
    radio.heard[alice] = now;
    await trip.tick();
    expect(trip.overdue, isEmpty);
    now = now.add(const Duration(minutes: 61));
    radio.heard[bob] = now;
    await trip.tick();
    expect(radio.alerts, hasLength(2));
  });

  test('no overdue alerts without an active trip', () async {
    await trip.updatePlan(trip.plan.copyWith(members: [alice], overdueMinutes: 30));
    now = now.add(const Duration(hours: 5));
    await trip.tick();
    expect(radio.alerts, isEmpty);
  });

  test('plan and check-ins persist; SOS does not', () async {
    await trip.updatePlan(trip.plan.copyWith(name: 'Ridge loop', members: [alice], reminderMinutes: 60));
    await trip.startTrip();
    await trip.checkIn('At camp');
    await trip.startSos();

    final again = BastionTripController(radio: radio, clock: () => now);
    await again.load();
    addTearDown(again.dispose);
    expect(again.plan.name, 'Ridge loop');
    expect(again.plan.members, [alice]);
    expect(again.plan.active, isTrue);
    expect(again.plan.startedAt, now);
    expect(again.lastCheckIn!.label, 'At camp');
    expect(again.sos.active, isFalse);
  });

  test('a trip has at most six contacts', () {
    expect(() => trip.updatePlan(trip.plan.copyWith(members: [1, 2, 3, 4, 5, 6, 7])), throwsArgumentError);
  });
}
