import '../generated/meshtastic/admin.pb.dart';
import '../generated/meshtastic/apponly.pb.dart';
import '../generated/meshtastic/channel.pb.dart';
import '../generated/meshtastic/config.pb.dart';
import 'bastion_settings_verifier.dart';

/// Why a channel import did not finish with a verified result.
class ChannelImportException implements Exception {
  const ChannelImportException(this.message, {required this.radioMayHaveChanged});
  final String message;

  /// False when the import was refused before anything was written.
  final bool radioMayHaveChanged;

  @override
  String toString() => message;
}

/// Adapter around the active radio; faked in channel import tests.
abstract interface class ChannelImportGateway {
  int? get localNodeNum;
  Future<Channel> readChannel(int index);
  Future<Config> readConfig(AdminMessage_ConfigType type);

  /// Writes [channels] and optional [lora] in one edit transaction.
  Future<void> writeChannelImport(List<Channel> channels, Config? lora);
  Future<void> waitForSettingsRadio(int nodeNum);
}

/// Applies a shared channel set, then confirms it with a fresh read from the
/// same radio. Writes once; an uncertain result is reported, never resent.
class BastionChannelImport {
  BastionChannelImport(this.radio);
  final ChannelImportGateway radio;

  /// [replace] overwrites all 8 slots and the LoRa config, as the official
  /// apps do for a plain link. Otherwise the link's channels go into free
  /// slots, skipping ones already present, and LoRa is left unchanged.
  /// Returns the number of channels from the link now on the radio.
  Future<int> apply(ChannelSet set, {required bool replace}) async {
    final node = radio.localNodeNum;
    if (node == null) {
      throw const ChannelImportException('Connect to a radio first.', radioMayHaveChanged: false);
    }
    final originals = [for (var i = 0; i < 8; i++) await radio.readChannel(i)];
    final writes = replace ? _replacement(set) : _additions(set, originals);
    if (writes.isEmpty) return 0;
    final lora = replace && set.hasLoraConfig() ? Config(lora: set.loraConfig) : null;
    final originalLora = lora == null ? null : await radio.readConfig(AdminMessage_ConfigType.LORA_CONFIG);
    if (radio.localNodeNum != node) {
      throw const ChannelImportException('Connected radio changed. Nothing was written.',
          radioMayHaveChanged: false);
    }

    try {
      await radio.writeChannelImport(writes, lora);
    } catch (error) {
      throw ChannelImportException('The import was interrupted before the radio confirmed it ($error). '
          'Some channels may have changed. Reconnect and check the channel list before importing again.',
          radioMayHaveChanged: true);
    }

    final List<String> mismatched;
    try {
      await radio.waitForSettingsRadio(node);
      if (radio.localNodeNum != node) throw StateError('Connected radio changed while verifying.');
      mismatched = [
        for (final wanted in writes)
          if (!BastionSettingsVerifier.matchesChanges(
              originals[wanted.index], wanted, await radio.readChannel(wanted.index)))
            'slot ${wanted.index}',
        if (lora != null && !BastionSettingsVerifier.matchesChanges(
            originalLora!, lora, await radio.readConfig(AdminMessage_ConfigType.LORA_CONFIG)))
          'LoRa settings',
      ];
      if (radio.localNodeNum != node) throw StateError('Connected radio changed while verifying.');
    } catch (error) {
      throw ChannelImportException('The radio accepted the import, but it could not be verified ($error). '
          'Reconnect to the same radio and check the channel list before importing again.',
          radioMayHaveChanged: true);
    }
    if (mismatched.isNotEmpty) {
      throw ChannelImportException('The radio accepted the import, but a fresh read does not match for '
          '${mismatched.join(', ')}. Check the channel list before importing again.',
          radioMayHaveChanged: true);
    }
    return replace ? set.settings.length : writes.length;
  }

  static List<Channel> _replacement(ChannelSet set) => [
        for (var i = 0; i < 8; i++)
          i < set.settings.length
              ? Channel(index: i, role: i == 0 ? Channel_Role.PRIMARY : Channel_Role.SECONDARY,
                  settings: set.settings[i])
              : Channel(index: i, role: Channel_Role.DISABLED),
      ];

  static List<Channel> _additions(ChannelSet set, List<Channel> existing) {
    bool present(ChannelSettings s) => existing.any((c) => c.role != Channel_Role.DISABLED &&
        c.settings.name == s.name && _sameBytes(c.settings.psk, s.psk));
    final toAdd = set.settings.where((s) => !present(s)).toList();
    final free = existing.where((c) => c.index != 0 && c.role == Channel_Role.DISABLED).toList();
    if (toAdd.length > free.length) {
      throw ChannelImportException(
          'Only ${free.length} free channel slots; the link has ${toAdd.length} new channels.',
          radioMayHaveChanged: false);
    }
    return [
      for (var i = 0; i < toAdd.length; i++)
        Channel(index: free[i].index, role: Channel_Role.SECONDARY, settings: toAdd[i]),
    ];
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
