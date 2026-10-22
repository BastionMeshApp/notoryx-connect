import 'package:shared_preferences/shared_preferences.dart';

import 'bastion_chat_message.dart';
import 'bastion_message_archive.dart';
import 'meshtastic_text_codec.dart';

/// Keeps chat history and the offline queue separate for each radio.
///
/// A radio is identified by its local node number. Unassigned history (saved
/// before this existed, or queued before any radio connected) moves to radios
/// the first time one connects: outgoing messages to the radio that sent them,
/// direct messages to the radio they were addressed to, everything else to
/// the radio connecting now. The original is kept under [migratedKey].
class BastionRadioHistory {
  BastionRadioHistory({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const lastRadioKey = 'bastion.comms.last_radio';
  static const migratedKey = '${BastionMessageArchive.key}.migrated';

  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  /// The radio whose history to show while disconnected; null if none yet.
  Future<int?> lastRadio() async {
    try {
      return await _store.getInt(lastRadioKey);
    } catch (_) {
      return null;
    }
  }

  /// The radio a stored message belongs to, when the message shows it.
  static int? attributedRadio(BastionChatMessage message) {
    if (message.direction == BastionMessageDirection.outgoing) {
      return message.from == 0 ? null : message.from;
    }
    return message.to == MeshtasticTextCodec.broadcastNode ? null : message.to;
  }

  /// Moves unassigned history to radios, remembers [radio] as the last one
  /// and returns its archive (not yet loaded).
  Future<BastionMessageArchive> open(int radio) async {
    await _migrateUnassigned(radio);
    try {
      await _store.setInt(lastRadioKey, radio);
    } catch (_) {
      // Only affects which history is shown offline next launch.
    }
    return BastionMessageArchive(preferences: _preferences, radio: radio);
  }

  Future<void> _migrateUnassigned(int radio) async {
    final unassigned = BastionMessageArchive(preferences: _preferences);
    final legacy = await unassigned.load();
    if (!unassigned.canSave || (legacy.messages.isEmpty && legacy.pending.isEmpty)) return;

    final messages = <int, List<BastionChatMessage>>{};
    for (final message in legacy.messages) {
      (messages[attributedRadio(message) ?? radio] ??= []).add(message);
    }
    final pending = {radio: legacy.pending};
    for (final target in {...messages.keys, radio}) {
      final archive = BastionMessageArchive(preferences: _preferences, radio: target);
      final existing = await archive.load();
      if (!archive.canSave) return;
      final saved = await archive.save(
        messages: mergeMessages(messages[target] ?? const [], existing.messages),
        pending: mergePending(pending[target] ?? const [], existing.pending),
      );
      if (!saved) return;
    }
    try {
      final raw = await _store.getString(BastionMessageArchive.key);
      if (raw != null) await _store.setString(migratedKey, raw);
      await _store.remove(BastionMessageArchive.key);
    } catch (_) {
      // Copies are already in the radio archives; a later merge dedupes.
    }
  }

  /// [older] then [newer] in time order, without duplicates, newest 500.
  static List<BastionChatMessage> mergeMessages(
      List<BastionChatMessage> older, List<BastionChatMessage> newer) {
    final seen = <String>{};
    final merged = [
      for (final m in [...older, ...newer])
        if (seen.add('${m.direction.name}:${m.from}:${m.packetId}')) m,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged.length <= 500 ? merged : merged.sublist(merged.length - 500);
  }

  static List<PendingTextMessage> mergePending(
      List<PendingTextMessage> older, List<PendingTextMessage> newer) {
    final seen = <int>{};
    return [for (final m in [...older, ...newer]) if (seen.add(m.packetId)) m];
  }
}
