import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../generated/meshtastic/mesh.pb.dart' as pb;
import 'bastion_phone_position.dart';

/// Local, bounded field records. Coordinates identify the receiver, not the sender.
class BastionFieldLog extends ChangeNotifier {
  static final instance = BastionFieldLog();
  final List<Map<String, Object?>> _records = [];
  List<Map<String, Object?>> get records { _trim(); return List.unmodifiable(_records.map(Map<String, Object?>.unmodifiable)); }
  String? error;
  Future<void> _pending = Future.value();
  final Map<int, DateTime> _lastPeer = {};
  int? _radio;
  bool recording = false;

  Future<void> load() async {
    try {
      final raw = await SharedPreferencesAsync().getString('bastion.field_log.v1');
      if (raw != null) {
        final decoded = jsonDecode(raw) as List;
        _records.addAll(decoded.map((e) => Map<String, Object?>.from(e as Map)));
        _trim();
      }
    } catch (_) { error = 'Saved field records could not be loaded. Recording is disabled.'; }
    notifyListeners();
  }

  void _trim() {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
    _records.removeWhere((r) => r['kind'] == 'coverage' && (r['time'] as String).compareTo(cutoff) < 0);
    while (_records.where((r) => r['kind'] == 'coverage').length > 2000) {
      _records.removeAt(_records.indexWhere((r) => r['kind'] == 'coverage'));
    }
  }

  Future<void> addIncident(String text, {int? radio}) async {
    if (text.trim().isEmpty || text.length > 1000) throw ArgumentError('Enter a note of 1–1000 characters.');
    if (error != null) throw StateError(error!);
    if (_records.where((r) => r['kind'] == 'incident').length >= 500) throw StateError('Incident log full. Export and remove an old note before adding another.');
    await _append({'kind': 'incident', 'time': DateTime.now().toUtc().toIso8601String(), 'radio': radio, 'note': text.trim()});
  }

  Future<void> removeIncident(Map<String, Object?> record) {
    final operation = _pending.then((_) async {
      final index = _records.indexWhere((r) => r['kind'] == 'incident' && r['time'] == record['time'] && r['note'] == record['note']);
      if (index < 0) return;
      final removed = _records.removeAt(index);
      try { await SharedPreferencesAsync().setString('bastion.field_log.v1', jsonEncode(_records)); }
      catch (_) { _records.insert(index, removed); rethrow; }
      notifyListeners();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  void start(int radio) {
    if (error != null) throw StateError(error!);
    _radio = radio;
    _lastPeer.clear();
    recording = true;
    notifyListeners();
  }

  void stop() { recording = false; _radio = null; _lastPeer.clear(); notifyListeners(); }

  /// Only fresh RF packets with a recent accurate receiver fix qualify.
  Future<void> observe(pb.MeshPacket packet, PhoneFix? fix, DateTime now) async {
    if (!recording || fix == null || packet.from == 0 || packet.from == 0xffffffff || packet.from == _radio || packet.viaMqtt) return;
    if (!packet.hasRxTime() || (!packet.hasRxSnr() && !packet.hasRxRssi())) return;
    final age = now.difference(DateTime.fromMillisecondsSinceEpoch(packet.rxTime * 1000, isUtc: true));
    final fixAge = now.difference(fix.time);
    if (age.isNegative || age > const Duration(minutes: 2) || fixAge.isNegative || fixAge > const Duration(seconds: 30)) return;
    if (fix.accuracyMeters == null || !fix.accuracyMeters!.isFinite || fix.accuracyMeters! > 50 || fix.accuracyMeters! < 0 ||
        !fix.latitude.isFinite || !fix.longitude.isFinite || fix.latitude.abs() > 90 || fix.longitude.abs() > 180) return;
    if (packet.id != 0 && _records.any((r) => r['kind'] == 'coverage' && r['radio'] == _radio && r['from'] == packet.from && r['packet'] == packet.id)) return;
    final last = _lastPeer[packet.from];
    if (last != null && now.difference(last) < const Duration(seconds: 30)) return;
    if (packet.hasRxSnr() && !packet.rxSnr.isFinite) return;
    _lastPeer[packet.from] = now;
    await _append({'kind': 'coverage', 'time': now.toUtc().toIso8601String(), 'radio': _radio,
      'from': packet.from, 'packet': packet.id, 'lat': fix.latitude, 'lon': fix.longitude,
      'accuracy': fix.accuracyMeters, 'snr': packet.hasRxSnr() ? packet.rxSnr : null,
      'rssi': packet.hasRxRssi() ? packet.rxRssi : null});
  }

  Future<void> _append(Map<String, Object?> record) {
    final operation = _pending.then((_) async {
      if (error != null) throw StateError(error!);
      if (record['kind'] == 'incident' && _records.where((r) => r['kind'] == 'incident').length >= 500) throw StateError('Incident log full. Export and remove an old note.');
      final previous = List<Map<String, Object?>>.of(_records);
      _records.add(record);
      _trim();
      try { await SharedPreferencesAsync().setString('bastion.field_log.v1', jsonEncode(_records)); }
      catch (_) {
        _records..clear()..addAll(previous);
        recording = false;
        error = 'Field records could not be saved. Recording stopped.';
        notifyListeners();
        rethrow;
      }
      notifyListeners();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  String exportCsv(String kind) {
    const fields = ['kind', 'time', 'radio', 'from', 'packet', 'lat', 'lon', 'accuracy', 'snr', 'rssi', 'note'];
    String cell(Object? v) {
      var text = v?.toString() ?? '';
      // Prevent spreadsheet formula evaluation of user-authored incident notes.
      if (text.isNotEmpty && '=+-@\t\r'.contains(text[0]) && v is String) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }
    return '${fields.join(',')}\r\n${records.where((r) => r['kind'] == kind).map((r) => fields.map((f) => cell(r[f])).join(',')).join('\r\n')}\r\n';
  }
}
