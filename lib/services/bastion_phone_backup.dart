import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';
import 'bastion_encrypted_backup.dart';

/// What a phone backup contains, shown before restoring it.
class PhoneBackupSummary {
  const PhoneBackupSummary({
    required this.exportedAt,
    required this.appVersion,
    required this.radios,
    required this.messages,
    required this.items,
  });

  final DateTime exportedAt;
  final String appVersion;

  /// Radios with saved chat history.
  final int radios;
  final int messages;

  /// Every stored setting and record, including the chat histories.
  final int items;
}

/// Encrypted backup of everything this app stores on the phone: chat
/// history and offline queues for every radio, NodeDex, waypoints, field
/// records, bot limits and app settings. Radio settings have their own backup.
///
/// Restore replaces all phone data with the backup's. It refuses a backup
/// from a newer format, and puts the previous data back if a write fails.
class BastionPhoneBackup {
  BastionPhoneBackup({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const format = 'notoryx-phone-backup';
  static const formatVersion = 1;
  static const prefix = 'bastion.';
  static const encryption = BastionEncryptedBackup(
      format: 'notoryx-encrypted-phone-backup', maxBytes: 8 * 1024 * 1024);

  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  /// Everything stored under [prefix], as plain JSON (encrypt before saving).
  Future<String> export({DateTime? now}) async {
    final values = await _readAll();
    return jsonEncode({
      'format': format,
      'formatVersion': formatVersion,
      'appVersion': bastionAppVersion,
      'exportedAtUtc': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'entries': {for (final e in values.entries) e.key: _encode(e.value)},
    });
  }

  /// Validates [plain] without changing anything.
  static (PhoneBackupSummary, Map<String, Object>) parse(String plain) {
    final Object? root;
    try {
      root = jsonDecode(plain);
    } on FormatException {
      throw const FormatException('This is not a NOTORYX Connect phone backup.');
    }
    if (root is! Map<String, Object?> || root['format'] != format) {
      throw const FormatException('This is not a NOTORYX Connect phone backup.');
    }
    final version = root['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw const FormatException('This backup was made by a newer version of '
          'NOTORYX Connect. Update the app, then restore it.');
    }
    final entries = root['entries'];
    final exported = DateTime.tryParse('${root['exportedAtUtc']}');
    if (entries is! Map<String, Object?> || exported == null) {
      throw const FormatException('Phone backup is incomplete.');
    }
    final values = <String, Object>{};
    var radios = 0, messages = 0;
    for (final e in entries.entries) {
      if (!e.key.startsWith(prefix)) {
        throw FormatException('Phone backup contains an unexpected item (${e.key}).');
      }
      final value = _decode(e.value);
      values[e.key] = value;
      if (e.key.startsWith('bastion.comms.archive.') && !e.key.endsWith('.unreadable') &&
          !e.key.endsWith('.migrated') && value is String) {
        radios += e.key.contains('.radio.') ? 1 : 0;
        try {
          final list = (jsonDecode(value) as Map)['messages'];
          if (list is List) messages += list.length;
        } catch (_) {
          // Counted only for the summary; the archive validates on load.
        }
      }
    }
    return (PhoneBackupSummary(exportedAt: exported.toLocal(), appVersion: '${root['appVersion']}',
        radios: radios, messages: messages, items: values.length), values);
  }

  /// Replaces all phone data with [values] from [parse]. If any write
  /// fails, the previous data is written back and the error rethrown.
  Future<void> restore(Map<String, Object> values) async {
    final previous = await _readAll();
    try {
      await _replace(values, previous.keys);
    } catch (error) {
      try {
        await _replace(previous, values.keys);
      } catch (_) {
        throw StateError('Restore failed ($error) and the previous phone data could not '
            'be fully put back. Restore the backup again before using the app.');
      }
      throw StateError('Restore failed ($error). Your previous phone data was put back.');
    }
  }

  Future<void> _replace(Map<String, Object> values, Iterable<String> otherKeys) async {
    for (final key in otherKeys) {
      if (!values.containsKey(key)) await _store.remove(key);
    }
    for (final e in values.entries) {
      final v = e.value;
      switch (v) {
        case String(): await _store.setString(e.key, v);
        case bool(): await _store.setBool(e.key, v);
        case int(): await _store.setInt(e.key, v);
        case double(): await _store.setDouble(e.key, v);
        case List<String>(): await _store.setStringList(e.key, v);
        default: throw StateError('Unsupported value for ${e.key}');
      }
    }
  }

  Future<Map<String, Object>> _readAll() async {
    final keys = (await _store.getKeys()).where((k) => k.startsWith(prefix));
    final all = await _store.getAll(allowList: keys.toSet());
    return {for (final e in all.entries) if (e.value != null) e.key: e.value!};
  }

  static Map<String, Object> _encode(Object value) => switch (value) {
    String() => {'type': 'string', 'value': value},
    bool() => {'type': 'bool', 'value': value},
    int() => {'type': 'int', 'value': value},
    double() => {'type': 'double', 'value': value},
    List() => {'type': 'stringList', 'value': [for (final v in value) '$v']},
    _ => throw StateError('Unsupported stored value ${value.runtimeType}'),
  };

  static Object _decode(Object? json) {
    if (json is Map<String, Object?>) {
      final value = json['value'];
      switch ((json['type'], value)) {
        case ('string', final String v): return v;
        case ('bool', final bool v): return v;
        case ('int', final int v): return v;
        case ('double', final num v): return v.toDouble();
        case ('stringList', final List v) when v.every((s) => s is String): return List<String>.from(v);
      }
    }
    throw const FormatException('Phone backup contains a damaged item.');
  }
}
