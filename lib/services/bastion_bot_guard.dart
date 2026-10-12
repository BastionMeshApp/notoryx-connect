import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bot airtime budget survives reconnects/restarts; enabling remains session-only.
class BastionBotGuard extends ChangeNotifier {
  static final instance = BastionBotGuard();
  bool quietEnabled = true;
  int quietStart = 22;
  int quietEnd = 7;
  int channel = 0;
  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool _reserving = false;
  final List<DateTime> _sent = [];
  final Map<int, DateTime> _peers = {};
  String? error;

  bool isQuiet(DateTime local) => quietEnabled && (quietStart == quietEnd ||
    (quietStart < quietEnd ? local.hour >= quietStart && local.hour < quietEnd
      : local.hour >= quietStart || local.hour < quietEnd));

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final p = SharedPreferencesAsync();
      final raw = await p.getString('bastion.bot.guard.v1');
      if (raw != null) {
        final data = jsonDecode(raw) as Map;
        quietEnabled = data['quiet'] as bool;
        quietStart = data['start'] as int;
        quietEnd = data['end'] as int;
        channel = data['channel'] as int;
        if (quietStart < 0 || quietStart > 23 || quietEnd < 0 || quietEnd > 23 || channel < 0 || channel > 7) throw const FormatException('Invalid bot preferences');
        _sent.addAll((data['sent'] as List).map((v) => DateTime.parse(v as String)));
        final peers = data['peers'] as Map;
        for (final entry in peers.entries) { _peers[int.parse(entry.key as String)] = DateTime.parse(entry.value as String); }
      }
      _loaded = true;
    } catch (_) { error = 'Bot safeguards could not be loaded. Automatic replies are blocked.'; }
    notifyListeners();
  }

  Future<void> update({bool? quiet, int? start, int? end, int? selectedChannel}) async {
    await load();
    if (error != null) return;
    quietEnabled = quiet ?? quietEnabled;
    quietStart = start ?? quietStart;
    quietEnd = end ?? quietEnd;
    channel = selectedChannel ?? channel;
    await _save();
    notifyListeners();
  }

  Future<void> _save() {
    final encoded = jsonEncode({
      'quiet': quietEnabled, 'start': quietStart, 'end': quietEnd, 'channel': channel,
      'sent': _sent.map((v) => v.toUtc().toIso8601String()).toList(),
      'peers': _peers.map((k, v) => MapEntry('$k', v.toUtc().toIso8601String())),
    });
    _writes = _writes.then((_) async {
      try { await SharedPreferencesAsync().setString('bastion.bot.guard.v1', encoded); }
      catch (_) { error = 'Bot safeguards could not be saved. Automatic replies are blocked.'; notifyListeners(); }
    });
    return _writes;
  }

  /// Reserve before sending, including failed sends, to avoid retry storms.
  Future<bool> reserve({required int sender, required int receivedChannel, required int? rxTime, required DateTime now}) async {
    if (_reserving) return false;
    _reserving = true;
    try {
      await load();
      if (error != null || sender == 0 || sender == 0xffffffff || receivedChannel != channel || isQuiet(now.toLocal()) || rxTime == null) return false;
      final age = now.difference(DateTime.fromMillisecondsSinceEpoch(rxTime * 1000, isUtc: true));
      if (age.isNegative || age > const Duration(minutes: 2)) return false;
      _sent.removeWhere((v) => now.difference(v) >= const Duration(hours: 1));
      _peers.removeWhere((_, v) => now.difference(v) >= const Duration(minutes: 5));
      if (_sent.length >= 6 || (_sent.isNotEmpty && now.difference(_sent.last) < const Duration(seconds: 30)) || _peers.containsKey(sender)) return false;
      _sent.add(now);
      _peers[sender] = now;
      await _save();
      return error == null && !isQuiet(now.toLocal()) && channel == receivedChannel;
    } finally { _reserving = false; }
  }
}
