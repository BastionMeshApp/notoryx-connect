import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bastion_chat_message.dart';

class BastionArchiveSnapshot {
  const BastionArchiveSnapshot({
    this.messages = const [],
    this.pending = const [],
  });

  final List<BastionChatMessage> messages;
  final List<PendingTextMessage> pending;
}

/// Small durable archive for COMMS history and the outbound offline queue.
///
/// Storage failures never stop messaging, but they are reported through
/// [problem], and stored history is never overwritten by an empty or partial
/// load: unreadable data is copied to [backupKey] first, and if storage can't
/// be read at all, saving stays off for this session.
class BastionMessageArchive extends ChangeNotifier {
  BastionMessageArchive({SharedPreferencesAsync? preferences, this.radio})
      : _preferences = preferences;

  /// Unassigned history: saved before history was kept per radio, or queued
  /// before any radio connected. [BastionRadioHistory] moves it to radios.
  static const key = 'bastion.comms.archive.v1';

  /// Holds the raw unassigned archive when it could not be fully read.
  static const backupKey = 'bastion.comms.archive.v1.unreadable';

  /// The local node number of the radio this history belongs to; null for
  /// unassigned history.
  final int? radio;

  /// Where this archive is stored.
  String get storageKey => radio == null ? key : radioKey(radio!);

  static String radioKey(int radio) =>
      'bastion.comms.archive.v2.radio.${radio.toRadixString(16).padLeft(8, '0')}';

  /// Whether saves are allowed; false after storage could not be read.
  bool get canSave => !_saveBlocked;

  SharedPreferencesAsync? _preferences;
  Future<BastionArchiveSnapshot>? _loading;
  bool _saveBlocked = false;
  String? _loadProblem;
  String? _saveProblem;
  Future<void> _saves = Future.value();

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  /// What went wrong with message storage, for the user; null when fine.
  String? get problem => _saveProblem ?? _loadProblem;

  Future<BastionArchiveSnapshot> load() => _loading = _load();

  Future<BastionArchiveSnapshot> _load() async {
    final String? raw;
    try {
      raw = await _store.getString(storageKey);
    } catch (error) {
      _saveBlocked = true;
      _setLoadProblem('Message history could not be read from phone storage. '
          'New messages are not saved until the app restarts, so stored history is not overwritten.');
      return const BastionArchiveSnapshot();
    }
    if (raw == null || raw.isEmpty) return const BastionArchiveSnapshot();

    Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      root = null;
    }
    if (root is! Map<String, Object?>) {
      await _keepUnreadable(raw, 'Saved message history was damaged and could not be loaded.');
      return const BastionArchiveSnapshot();
    }

    final Map<String, Object?> map = root;
    var skipped = 0;
    List<T> entries<T>(String name, T Function(Map<String, Object?>) read) {
      final values = map[name];
      if (values is! List) {
        if (values != null) skipped++;
        return [];
      }
      final result = <T>[];
      for (final value in values) {
        try {
          result.add(read(value as Map<String, Object?>));
        } catch (_) {
          skipped++;
        }
      }
      return result;
    }

    final snapshot = BastionArchiveSnapshot(
      messages: entries('messages', BastionChatMessage.fromJson),
      pending: entries('pending', PendingTextMessage.fromJson),
    );
    if (skipped > 0) {
      await _keepUnreadable(raw,
          '$skipped saved message${skipped == 1 ? '' : 's'} could not be read and ${skipped == 1 ? 'was' : 'were'} skipped.');
    }
    return snapshot;
  }

  /// Copies [raw] aside before any save may replace it.
  Future<void> _keepUnreadable(String raw, String what) async {
    try {
      await _store.setString('$storageKey.unreadable', raw);
      _setLoadProblem('$what A copy of the original data was kept on this phone.');
    } catch (_) {
      _saveBlocked = true;
      _setLoadProblem('$what It could not be backed up, so new messages are not saved '
          'until the app restarts.');
    }
  }

  void _setLoadProblem(String message) {
    _loadProblem = message;
    notifyListeners();
  }

  /// Saves a snapshot taken now. Saves run one at a time in call order and
  /// wait for a load in progress. Returns whether the snapshot was stored.
  Future<bool> save({
    required List<BastionChatMessage> messages,
    required List<PendingTextMessage> pending,
  }) {
    final encoded = jsonEncode({
      'messages': messages.takeLast(500).map((m) => m.toJson()).toList(),
      'pending': pending.map((m) => m.toJson()).toList(),
    });
    final result = _saves.then((_) => _write(encoded));
    _saves = result;
    return result;
  }

  Future<bool> _write(String encoded) async {
    await _loading;
    if (_saveBlocked) return false;
    try {
      await _store.setString(storageKey, encoded);
      if (_saveProblem != null) {
        _saveProblem = null;
        notifyListeners();
      }
      return true;
    } catch (error) {
      _saveProblem = 'Messages could not be saved to phone storage ($error). '
          'Recent messages and the offline queue may be lost if the app closes.';
      notifyListeners();
      return false;
    }
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.skip(list.length - count);
  }
}
