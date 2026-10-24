import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bastion_chat_message.dart';
import 'bastion_field_alerts.dart';

/// Check-in choices, in the order the buttons show them.
const checkInLabels = ["I'm OK", 'At camp', 'Delayed', 'Heading back'];

/// Time between SOS repeats; keeps an emergency from flooding the mesh.
const sosRepeatInterval = Duration(minutes: 5);

/// SOS transmissions per activation (the first plus repeats): one hour.
const sosMaxSends = 12;

/// Check-in reminder choices in minutes; 0 is off.
const reminderChoices = [0, 30, 60, 120, 240];

/// Overdue alert choices in minutes; 0 is off.
const overdueChoices = [0, 30, 60, 120, 240, 480];

/// Field messages stay well inside Meshtastic's text payload.
const fieldMessageLimit = 200;

/// A planned trip: who gets check-ins and SOS, and when to warn.
@immutable
class TripPlan {
  const TripPlan({
    this.name = 'My trip',
    this.members = const [],
    this.active = false,
    this.startedAt,
    this.overdueMinutes = 60,
    this.reminderMinutes = 0,
    this.sosChannel = -1,
  });

  final String name;

  /// Node numbers of the trip contacts (at most [maxMembers]).
  final List<int> members;
  final bool active;
  final DateTime? startedAt;

  /// Warn when a trip contact is silent this long; 0 is off.
  final int overdueMinutes;

  /// Remind me to check in this long after my last check-in; 0 is off.
  final int reminderMinutes;

  /// Channel an SOS is also broadcast on, or -1 for trip contacts only.
  final int sosChannel;

  static const maxMembers = 6;

  TripPlan copyWith({
    String? name,
    List<int>? members,
    bool? active,
    DateTime? startedAt,
    bool clearStartedAt = false,
    int? overdueMinutes,
    int? reminderMinutes,
    int? sosChannel,
  }) => TripPlan(
    name: name ?? this.name,
    members: members ?? this.members,
    active: active ?? this.active,
    startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
    overdueMinutes: overdueMinutes ?? this.overdueMinutes,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    sosChannel: sosChannel ?? this.sosChannel,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'members': members,
    'active': active,
    'startedAt': startedAt?.millisecondsSinceEpoch,
    'overdueMinutes': overdueMinutes,
    'reminderMinutes': reminderMinutes,
    'sosChannel': sosChannel,
  };

  static TripPlan fromJson(Map<String, Object?> json) => TripPlan(
    name: json['name'] as String? ?? 'My trip',
    members: [for (final m in json['members'] as List? ?? const []) m as int],
    active: json['active'] as bool? ?? false,
    startedAt: json['startedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(json['startedAt']! as int, isUtc: true),
    overdueMinutes: json['overdueMinutes'] as int? ?? 60,
    reminderMinutes: json['reminderMinutes'] as int? ?? 0,
    sosChannel: json['sosChannel'] as int? ?? -1,
  );
}

/// One check-in and the direct message sent to each trip contact.
@immutable
class CheckInRecord {
  const CheckInRecord({required this.label, required this.at, required this.text, required this.packets});

  final String label;
  final DateTime at;
  final String text;

  /// Packet id of the latest message to each contact (a resend replaces it).
  final Map<int, int> packets;

  CheckInRecord withPackets(Map<int, int> update) =>
      CheckInRecord(label: label, at: at, text: text, packets: {...packets, ...update});

  Map<String, Object?> toJson() => {
    'label': label,
    'at': at.millisecondsSinceEpoch,
    'text': text,
    'packets': {for (final e in packets.entries) '${e.key}': e.value},
  };

  static CheckInRecord fromJson(Map<String, Object?> json) => CheckInRecord(
    label: json['label']! as String,
    at: DateTime.fromMillisecondsSinceEpoch(json['at']! as int, isUtc: true),
    text: json['text'] as String? ?? '',
    packets: {
      for (final e in (json['packets'] as Map? ?? const {}).entries)
        int.parse(e.key as String): e.value as int,
    },
  );
}

/// The SOS for this app session; never resumed after a restart.
@immutable
class SosState {
  const SosState({this.active = false, this.startedAt, this.lastSentAt, this.sends = 0, this.acknowledgedBy});

  final bool active;
  final DateTime? startedAt;
  final DateTime? lastSentAt;
  final int sends;

  /// Name of the trip contact whose reply acknowledged the SOS.
  final String? acknowledgedBy;

  static const idle = SosState();

  /// Whether another transmission is due at [now].
  bool dueAt(DateTime now) =>
      active &&
      acknowledgedBy == null &&
      sends < sosMaxSends &&
      (lastSentAt == null || now.difference(lastSentAt!) >= sosRepeatInterval);

  /// When the next repeat goes out, or null when none will.
  DateTime? get nextSendAt =>
      !active || acknowledgedBy != null || sends >= sosMaxSends ? null : lastSentAt?.add(sosRepeatInterval);

  SosState sent(DateTime at) => SosState(
    active: active, startedAt: startedAt, lastSentAt: at, sends: sends + 1, acknowledgedBy: acknowledgedBy);

  SosState acknowledged(String by) => SosState(
    active: active, startedAt: startedAt, lastSentAt: lastSentAt, sends: sends, acknowledgedBy: by);
}

String _stamp(DateTime at) => at.toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ');

bool _usablePosition(double? lat, double? lon) =>
    lat != null && lon != null && lat.isFinite && lon.isFinite &&
    lat.abs() <= 90 && lon.abs() <= 180 && (lat.abs() > 0.000001 || lon.abs() > 0.000001);

String _withExtras(String text, {double? latitude, double? longitude, int? battery, bool sayNoPosition = false}) {
  if (_usablePosition(latitude, longitude)) {
    text += ' | Pos ${latitude!.toStringAsFixed(5)},${longitude!.toStringAsFixed(5)}';
  } else if (sayNoPosition) {
    text += ' | No position';
  }
  // 101 means external power, not a battery level.
  if (battery != null && battery >= 0 && battery <= 100) text += ' | Battery $battery%';
  if (utf8.encode(text).length > fieldMessageLimit) {
    throw ArgumentError('Message exceeds the $fieldMessageLimit-byte limit.');
  }
  return text;
}

/// A check-in message, as sent to each trip contact.
String checkInText(String label, DateTime at, {double? latitude, double? longitude, int? battery}) =>
    _withExtras('[NOTORYX Check-in] $label | ${_stamp(at)} UTC',
        latitude: latitude, longitude: longitude, battery: battery);

/// The SOS message. It always says whether a position is included, because
/// that is what responders need first.
String sosText(DateTime at, {double? latitude, double? longitude, int? battery}) =>
    _withExtras('[NOTORYX SOS] Need help | ${_stamp(at)} UTC',
        latitude: latitude, longitude: longitude, battery: battery, sayNoPosition: true);

/// Sent once when an SOS is stopped and the sender said they are safe.
String sosAllClearText(DateTime at) => '[NOTORYX SOS] All clear | ${_stamp(at)} UTC';

/// Trip contacts not heard for [overdue]. Time before the trip started
/// doesn't count, so nobody is overdue the moment a trip starts.
List<int> overdueMembers({
  required List<int> members,
  required DateTime? Function(int) lastHeard,
  required DateTime tripStarted,
  required DateTime now,
  required Duration overdue,
}) => members.where((member) {
  final heard = lastHeard(member);
  final since = heard == null || heard.isBefore(tripStarted) ? tripStarted : heard;
  return now.difference(since) >= overdue;
}).toList();

/// What the trip controller needs from the radio; faked in tests.
abstract interface class TripRadio {
  bool get isReady;
  int? get localNodeNum;
  ({double? latitude, double? longitude, int? battery}) get localStatus;
  List<BastionChatMessage> get messages;
  DateTime? lastHeard(int node);
  String nodeName(int node);
  Future<int> sendText({required String text, required int destination, required int channel});
  void alert(BastionFieldAlert alert);
}

/// Trip contacts, check-ins with per-contact delivery, SOS with repeats,
/// check-in reminders and overdue alerts. Alerts are phone notifications;
/// only check-ins and SOS are transmitted.
class BastionTripController extends ChangeNotifier {
  BastionTripController({required TripRadio radio, DateTime Function()? clock, SharedPreferencesAsync? preferences})
      : _radio = radio,
        _clock = clock ?? DateTime.now,
        _preferences = preferences;

  static const _key = 'bastion.trip.v1';
  static const _keptCheckIns = 20;

  final TripRadio _radio;
  final DateTime Function() _clock;
  SharedPreferencesAsync? _preferences;
  Timer? _timer;

  TripPlan _plan = const TripPlan();
  List<CheckInRecord> _checkIns = const [];
  SosState _sos = SosState.idle;
  bool _reminderShown = false;
  final Set<int> _overdueAlerted = {};
  String? _problem;

  SharedPreferencesAsync get _store => _preferences ??= SharedPreferencesAsync();

  TripPlan get plan => _plan;

  /// Check-ins, newest first.
  List<CheckInRecord> get checkIns => _checkIns;
  CheckInRecord? get lastCheckIn => _checkIns.isEmpty ? null : _checkIns.first;
  SosState get sos => _sos;

  /// The latest send or storage problem, for the user; null when fine.
  String? get problem => _problem;

  /// Trip contacts currently overdue.
  List<int> get overdue {
    final started = _plan.startedAt;
    if (!_plan.active || started == null || _plan.overdueMinutes == 0) return const [];
    return overdueMembers(
      members: _plan.members,
      lastHeard: _radio.lastHeard,
      tripStarted: started,
      now: _clock(),
      overdue: Duration(minutes: _plan.overdueMinutes),
    );
  }

  Future<void> load() async {
    try {
      final raw = await _store.getString(_key);
      if (raw != null) {
        final json = (jsonDecode(raw) as Map).cast<String, Object?>();
        _plan = TripPlan.fromJson((json['plan'] as Map).cast<String, Object?>());
        _checkIns = [
          for (final c in json['checkIns'] as List? ?? const [])
            CheckInRecord.fromJson((c as Map).cast<String, Object?>()),
        ];
      }
    } catch (_) {
      _problem = 'Saved trip details could not be read; the trip starts empty.';
    }
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => tick());
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.setString(_key, jsonEncode({
        'plan': _plan.toJson(),
        'checkIns': [for (final c in _checkIns) c.toJson()],
      }));
    } catch (error) {
      _problem = 'Trip details could not be saved ($error).';
    }
  }

  Future<void> updatePlan(TripPlan plan) async {
    if (plan.members.length > TripPlan.maxMembers) {
      throw ArgumentError('A trip has at most ${TripPlan.maxMembers} contacts.');
    }
    _plan = plan;
    await _save();
    notifyListeners();
  }

  Future<void> startTrip() async {
    _overdueAlerted.clear();
    _reminderShown = false;
    await updatePlan(_plan.copyWith(active: true, startedAt: _clock().toUtc()));
  }

  Future<void> stopTrip() => updatePlan(_plan.copyWith(active: false, clearStartedAt: true));

  /// Why a check-in can't be sent now, or null when it can.
  String? get checkInBlocked {
    if (!_radio.isReady) return 'Connect to a radio to check in.';
    if (_plan.members.isEmpty) return 'Choose trip contacts first.';
    return null;
  }

  /// Why an SOS can't be sent now, or null when it can.
  String? get sosBlocked {
    if (!_radio.isReady) return 'Connect to a radio to send an SOS.';
    if (_plan.members.isEmpty && _plan.sosChannel < 0) {
      return 'Choose trip contacts or an SOS channel first.';
    }
    return null;
  }

  /// Sends [label] as a direct message to every trip contact.
  Future<void> checkIn(String label) async {
    final blocked = checkInBlocked;
    if (blocked != null) throw StateError(blocked);
    final now = _clock().toUtc();
    final status = _radio.localStatus;
    final text = checkInText(label, now,
        latitude: status.latitude, longitude: status.longitude, battery: status.battery);
    final packets = await _sendToMembers(text, _plan.members);
    _checkIns = [CheckInRecord(label: label, at: now, text: text, packets: packets), ..._checkIns]
        .take(_keptCheckIns).toList();
    _reminderShown = false;
    await _save();
    notifyListeners();
  }

  /// Delivery of [record] per contact, from the radio's acknowledgments.
  Map<int, BastionDeliveryState> delivery(CheckInRecord record) {
    final byPacket = {for (final m in _radio.messages) m.packetId: m.deliveryState};
    return {
      for (final e in record.packets.entries) e.key: byPacket[e.value] ?? BastionDeliveryState.queued,
    };
  }

  /// Sends the latest check-in again to contacts it did not reach.
  Future<void> resendFailed() async {
    final record = lastCheckIn;
    if (record == null) return;
    final failed = [
      for (final e in delivery(record).entries)
        if (e.value == BastionDeliveryState.failed) e.key,
    ];
    if (failed.isEmpty) return;
    final packets = await _sendToMembers(record.text, failed);
    _checkIns = [record.withPackets(packets), ..._checkIns.skip(1)];
    await _save();
    notifyListeners();
  }

  Future<Map<int, int>> _sendToMembers(String text, List<int> members) async {
    final packets = <int, int>{};
    Object? lastError;
    for (final member in members) {
      try {
        packets[member] = await _radio.sendText(text: text, destination: member, channel: 0);
      } catch (error) {
        lastError = error;
      }
    }
    _problem = lastError == null ? null : 'Not every message could be queued ($lastError).';
    return packets;
  }

  /// Starts an SOS: sends now, then repeats every [sosRepeatInterval] until
  /// a trip contact replies, it is stopped, or [sosMaxSends] are sent.
  Future<void> startSos() async {
    final blocked = sosBlocked;
    if (blocked != null) throw StateError(blocked);
    final now = _clock().toUtc();
    _sos = SosState(active: true, startedAt: now);
    notifyListeners();
    await _sendSos(now);
  }

  /// Stops the SOS. With [allClear] the recipients are told you are safe.
  Future<void> stopSos({bool allClear = false}) async {
    if (!_sos.active) return;
    _sos = SosState.idle;
    notifyListeners();
    if (allClear && _radio.isReady) {
      final text = sosAllClearText(_clock().toUtc());
      await _sendToMembers(text, _plan.members);
      if (_plan.sosChannel >= 0) await _broadcast(text, _plan.sosChannel);
      notifyListeners();
    }
  }

  Future<void> _sendSos(DateTime now) async {
    final status = _radio.localStatus;
    final text = sosText(now, latitude: status.latitude, longitude: status.longitude, battery: status.battery);
    _sos = _sos.sent(now);
    await _sendToMembers(text, _plan.members);
    if (_plan.sosChannel >= 0) await _broadcast(text, _plan.sosChannel);
    notifyListeners();
  }

  Future<void> _broadcast(String text, int channel) async {
    try {
      await _radio.sendText(text: text, destination: 0xffffffff, channel: channel);
    } catch (error) {
      _problem = 'SOS could not be queued on channel $channel ($error).';
    }
  }

  /// Runs SOS repeats and acknowledgment, check-in reminders and overdue
  /// alerts. Called every 30 seconds while the app runs.
  @visibleForTesting
  Future<void> tick() async {
    final now = _clock().toUtc();
    if (_sos.active) {
      final by = _sosReply();
      if (by != null && _sos.acknowledgedBy == null) {
        _sos = _sos.acknowledged(by);
        _radio.alert(BastionFieldAlert(BastionAlertKind.sosAcknowledged, 0,
            'SOS acknowledged', '$by replied to your SOS.'));
        notifyListeners();
      } else if (_sos.dueAt(now) && _radio.isReady) {
        await _sendSos(now);
      }
    }
    if (!_plan.active) return;
    if (_plan.reminderMinutes > 0 && !_reminderShown) {
      final since = lastCheckIn?.at ?? _plan.startedAt;
      if (since != null && now.difference(since) >= Duration(minutes: _plan.reminderMinutes)) {
        _reminderShown = true;
        _radio.alert(const BastionFieldAlert(BastionAlertKind.checkInDue, 0,
            'Time to check in', 'Open NOTORYX Connect and send a check-in to your trip contacts.'));
      }
    }
    final late = overdue.toSet();
    _overdueAlerted.removeWhere((m) => !late.contains(m));
    for (final member in late.difference(_overdueAlerted)) {
      _overdueAlerted.add(member);
      _radio.alert(BastionFieldAlert(BastionAlertKind.contactOverdue, member,
          '${_radio.nodeName(member)} is overdue',
          'Not heard for over ${_plan.overdueMinutes} minutes during ${_plan.name}.'));
    }
  }

  /// The trip contact who sent a direct message after the SOS started.
  String? _sosReply() {
    final started = _sos.startedAt;
    final me = _radio.localNodeNum;
    if (started == null || me == null) return null;
    for (final m in _radio.messages.reversed) {
      if (m.direction == BastionMessageDirection.incoming &&
          m.to == me &&
          _plan.members.contains(m.from) &&
          !m.timestamp.isBefore(started)) {
        return _radio.nodeName(m.from);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
