import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which local field alerts are on, and their thresholds.
@immutable
class BastionAlertSettings {
  const BastionAlertSettings({
    this.lowBattery = true,
    this.batteryThreshold = 20,
    this.newNode = false,
    this.favoriteSilent = false,
    this.silence = const Duration(hours: 2),
  });

  static const key = 'bastion.alerts.v1';
  static const batteryChoices = [10, 20, 30];
  static const silenceChoices = [
    Duration(minutes: 30), Duration(hours: 1), Duration(hours: 2), Duration(hours: 6),
  ];

  /// Your radio or a favorite node at or below [batteryThreshold] percent.
  final bool lowBattery;
  final int batteryThreshold;

  /// This radio hears a node it has never heard before.
  final bool newNode;

  /// A favorite node is not heard for [silence] while connected.
  final bool favoriteSilent;
  final Duration silence;

  BastionAlertSettings copyWith({bool? lowBattery, int? batteryThreshold, bool? newNode,
      bool? favoriteSilent, Duration? silence}) => BastionAlertSettings(
    lowBattery: lowBattery ?? this.lowBattery,
    batteryThreshold: batteryThreshold ?? this.batteryThreshold,
    newNode: newNode ?? this.newNode,
    favoriteSilent: favoriteSilent ?? this.favoriteSilent,
    silence: silence ?? this.silence,
  );

  Map<String, Object> toJson() => {
    'lowBattery': lowBattery, 'batteryThreshold': batteryThreshold,
    'newNode': newNode, 'favoriteSilent': favoriteSilent, 'silenceMinutes': silence.inMinutes,
  };

  /// Unknown or out-of-range values fall back to the defaults.
  static BastionAlertSettings fromJson(Object? json) {
    const d = BastionAlertSettings();
    if (json is! Map) return d;
    final battery = json['batteryThreshold'];
    final minutes = json['silenceMinutes'];
    return BastionAlertSettings(
      lowBattery: json['lowBattery'] is bool ? json['lowBattery'] as bool : d.lowBattery,
      batteryThreshold: batteryChoices.contains(battery) ? battery as int : d.batteryThreshold,
      newNode: json['newNode'] is bool ? json['newNode'] as bool : d.newNode,
      favoriteSilent: json['favoriteSilent'] is bool ? json['favoriteSilent'] as bool : d.favoriteSilent,
      silence: silenceChoices.firstWhere((c) => c.inMinutes == minutes, orElse: () => d.silence),
    );
  }

  static Future<BastionAlertSettings> load([SharedPreferencesAsync? store]) async {
    try {
      final raw = await (store ?? SharedPreferencesAsync()).getString(key);
      return raw == null ? const BastionAlertSettings() : fromJson(jsonDecode(raw));
    } catch (_) {
      return const BastionAlertSettings();
    }
  }

  /// Returns false when the choice could not be saved (it still applies now).
  Future<bool> save([SharedPreferencesAsync? store]) async {
    try {
      await (store ?? SharedPreferencesAsync()).setString(key, jsonEncode(toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool operator ==(Object other) => other is BastionAlertSettings &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

enum BastionAlertKind { lowBattery, newNode, favoriteSilent, sosAcknowledged, checkInDue, contactOverdue }

@immutable
class BastionFieldAlert {
  const BastionFieldAlert(this.kind, this.nodeNum, this.title, this.body);
  final BastionAlertKind kind;
  final int nodeNum;
  final String title;
  final String body;

  /// Stable per condition, so a repeat replaces rather than stacks.
  int get notificationId => (kind.index << 28 ^ nodeNum) & 0x7fffffff;
}

/// Decides local field alerts from verified radio observations. Nothing is
/// ever transmitted. Each condition alerts once and rearms only after it
/// recovers; nothing alerts outside a connected session.
class BastionFieldAlertEngine {
  BastionFieldAlertEngine({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Battery must rise this far above the threshold before it can alert again.
  static const batteryHysteresis = 5;

  final DateTime Function() _clock;
  final Set<String> _active = {};
  DateTime? _sessionStart;
  int? _localNode;

  bool get inSession => _sessionStart != null;

  /// Call when the radio is ready (after its node list has synchronized).
  void startSession(int localNode) {
    _active.clear();
    _localNode = localNode;
    _sessionStart = _clock();
  }

  void endSession() {
    _active.clear();
    _sessionStart = null;
    _localNode = null;
  }

  /// Fresh battery telemetry from [nodeNum]. Only your radio and favorites
  /// alert. Unknown (null) and external power (above 100) never alert.
  BastionFieldAlert? battery(int nodeNum, int? level, String name,
      {required bool favorite, required BastionAlertSettings settings}) {
    if (!inSession || !settings.lowBattery || level == null || level < 0 || level > 100) return null;
    final isLocal = nodeNum == _localNode;
    if (!isLocal && !favorite) return null;
    final key = 'battery:$nodeNum';
    if (level > settings.batteryThreshold + batteryHysteresis) {
      _active.remove(key);
      return null;
    }
    if (level > settings.batteryThreshold || !_active.add(key)) return null;
    return BastionFieldAlert(BastionAlertKind.lowBattery, nodeNum,
        isLocal ? 'Your radio battery is low' : '$name battery is low',
        isLocal ? 'Your radio reports $level% battery.' : '$name reports $level% battery.');
  }

  /// A node update heard live. [knownBefore] says whether this radio had
  /// heard the node before this update.
  BastionFieldAlert? nodeHeard(int nodeNum, String name,
      {required bool knownBefore, required BastionAlertSettings settings}) {
    _active.remove('silent:$nodeNum');
    if (!inSession || !settings.newNode || knownBefore || nodeNum == _localNode) return null;
    if (!_active.add('new:$nodeNum')) return null;
    return BastionFieldAlert(BastionAlertKind.newNode, nodeNum, 'New node: $name',
        'Your radio heard $name for the first time.');
  }

  /// Favorites not heard for [BastionAlertSettings.silence] during this
  /// session. Call periodically while connected.
  List<BastionFieldAlert> checkSilence(
      Iterable<({int num, String name, DateTime? lastHeard})> favorites,
      BastionAlertSettings settings) {
    final start = _sessionStart;
    if (start == null || !settings.favoriteSilent) return const [];
    final now = _clock();
    final alerts = <BastionFieldAlert>[];
    for (final f in favorites) {
      if (f.num == _localNode) continue;
      final heard = f.lastHeard;
      final since = heard != null && heard.isAfter(start) ? heard : start;
      final key = 'silent:${f.num}';
      if (now.difference(since) < settings.silence) {
        _active.remove(key);
      } else if (_active.add(key)) {
        alerts.add(BastionFieldAlert(BastionAlertKind.favoriteSilent, f.num,
            '${f.name} has gone quiet',
            'Not heard for ${_describe(now.difference(since))}.'));
      }
    }
    return alerts;
  }

  static String _describe(Duration d) =>
      d.inHours >= 1 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';
}
