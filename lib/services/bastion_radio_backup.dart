import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../app_version.dart';
import '../generated/meshtastic/admin.pb.dart';
import '../generated/meshtastic/channel.pb.dart';
import '../generated/meshtastic/config.pb.dart';
import '../generated/meshtastic/mesh.pb.dart' show User;
import '../generated/meshtastic/module_config.pb.dart';

/// Validated settings staged in memory before any radio write.
class RadioBackupSnapshot {
  RadioBackupSnapshot({required this.owner, required this.configs,
    required this.modules, required this.channels, required this.firmware,
    required this.nodeNum, required this.createdAt});
  final User owner;
  final List<Config> configs;
  final List<ModuleConfig> modules;
  final List<Channel> channels;
  final String firmware;
  final int nodeNum;
  final DateTime createdAt;

  static AdminMessage_ConfigType configType(Config c) {
    final index = c.whichPayloadVariant().index;
    if (index >= AdminMessage_ConfigType.values.length || c.hasSecurity() || c.hasSessionkey()) {
      throw const FormatException('Security keys and session credentials cannot be restored.');
    }
    return AdminMessage_ConfigType.values[index];
  }
  static AdminMessage_ModuleConfigType moduleType(ModuleConfig m) {
    final index = m.whichPayloadVariant().index;
    if (index >= AdminMessage_ModuleConfigType.values.length) {
      throw const FormatException('Unsupported module settings.');
    }
    return AdminMessage_ModuleConfigType.values[index];
  }

  void validate() {
    if (configs.isEmpty || configs.length > 8 || modules.length > 17 || channels.length != 8 ||
        nodeNum <= 0 || firmware.isEmpty || owner.longName.isEmpty || owner.shortName.isEmpty) {
      throw const FormatException('Incomplete radio backup.');
    }
    if (configs.map(configType).toSet().length != configs.length ||
        modules.map(moduleType).toSet().length != modules.length ||
        channels.map((c) => c.index).toSet().length != 8 ||
        channels.any((c) => c.index < 0 || c.index > 7 ||
          ![0, 1, 16, 32].contains(c.settings.psk.length)) ||
        channels.where((c) => c.role == Channel_Role.PRIMARY).length != 1 ||
        channels.firstWhere((c) => c.index == 0).role != Channel_Role.PRIMARY) {
      throw const FormatException('Invalid or duplicate radio settings.');
    }
  }

  Future<String> encode() async {
    validate();
    final payload = jsonEncode({'owner': base64Encode(owner.writeToBuffer()),
      'configs': configs.map((c) => base64Encode(c.writeToBuffer())).toList(),
      'modules': modules.map((m) => base64Encode(m.writeToBuffer())).toList(),
      'channels': channels.map((c) => base64Encode(c.writeToBuffer())).toList(),
      'firmware': firmware, 'nodeNum': nodeNum});
    final hash = await Sha256().hash(utf8.encode(payload));
    return jsonEncode({'format': 'bastion-radio-settings', 'formatVersion': 1,
      'schemaVersion': 1, 'appVersion': bastionAppVersion,
      'exportedAtUtc': createdAt.toUtc().toIso8601String(),
      'payloadSha256': base64Encode(hash.bytes), 'payload': payload});
  }

  static Future<RadioBackupSnapshot> decode(String text) async {
    try {
      final e = jsonDecode(text) as Map<String, dynamic>;
      if (e['format'] != 'bastion-radio-settings' || e['formatVersion'] != 1 || e['schemaVersion'] != 1) {
        throw const FormatException('Unsupported backup version.');
      }
      final payload = e['payload'] as String;
      final hash = await Sha256().hash(utf8.encode(payload));
      if (base64Encode(hash.bytes) != e['payloadSha256']) {
        throw const FormatException('Backup checksum does not match.');
      }
      final p = jsonDecode(payload) as Map<String, dynamic>;
      List<T> list<T>(String key, T Function(List<int>) read) =>
        (p[key] as List).map((v) => read(base64Decode(v as String))).toList();
      final owner = User.fromBuffer(base64Decode(p['owner'] as String));
      // Hardware identity and device cryptographic identity are never cloned.
      final result = RadioBackupSnapshot(
        owner: User(longName: owner.longName, shortName: owner.shortName, isLicensed: owner.isLicensed),
        configs: list('configs', Config.fromBuffer), modules: list('modules', ModuleConfig.fromBuffer),
        channels: list('channels', Channel.fromBuffer), firmware: p['firmware'] as String,
        nodeNum: p['nodeNum'] as int, createdAt: DateTime.parse(e['exportedAtUtc'] as String));
      result.validate();
      return result;
    } on FormatException { rethrow; }
    catch (_) { throw const FormatException('Malformed radio backup.'); }
  }
}

/// Adapter around the active radio; faked in restore acceptance tests.
abstract interface class RadioBackupGateway {
  int get backupNodeNum;
  String get backupFirmware;
  List<AdminMessage_ConfigType> get backupConfigTypes;
  List<AdminMessage_ModuleConfigType> get backupModuleTypes;
  Future<User> readOwner();
  Future<Config> readConfig(AdminMessage_ConfigType type);
  Future<ModuleConfig> readModuleConfig(AdminMessage_ModuleConfigType type);
  Future<Channel> readChannel(int index);
  Future<void> writeBackup(RadioBackupSnapshot snapshot);
  Future<void> waitForBackupRadio(int nodeNum);
}

/// Captures fresh reads, preflights target support, and verifies restored values.
class BastionRadioBackup {
  BastionRadioBackup(this.radio);
  final RadioBackupGateway radio;

  Future<RadioBackupSnapshot> capture() async {
    final node = radio.backupNodeNum;
    final firmware = radio.backupFirmware;
    final configTypes = List<AdminMessage_ConfigType>.of(radio.backupConfigTypes);
    final moduleTypes = List<AdminMessage_ModuleConfigType>.of(radio.backupModuleTypes);
    final owner = await radio.readOwner();
    final configs = <Config>[];
    for (final type in configTypes) { configs.add(await radio.readConfig(type)); }
    final modules = <ModuleConfig>[];
    for (final type in moduleTypes) { modules.add(await radio.readModuleConfig(type)); }
    final channels = <Channel>[];
    for (var i = 0; i < 8; i++) { channels.add(await radio.readChannel(i)); }
    if (radio.backupNodeNum != node) throw StateError('Connected radio changed.');
    final snapshot = RadioBackupSnapshot(
      owner: User(longName: owner.longName, shortName: owner.shortName, isLicensed: owner.isLicensed),
      configs: configs, modules: modules, channels: channels, firmware: firmware,
      nodeNum: node, createdAt: DateTime.now());
    snapshot.validate();
    return snapshot;
  }

  Future<void> restore(RadioBackupSnapshot snapshot) async {
    snapshot.validate();
    final target = radio.backupNodeNum;
    // Refuse sections the target firmware did not advertise before writing.
    if (snapshot.configs.any((c) => !radio.backupConfigTypes.contains(RadioBackupSnapshot.configType(c))) ||
        snapshot.modules.any((m) => !radio.backupModuleTypes.contains(RadioBackupSnapshot.moduleType(m)))) {
      throw const FormatException('Target firmware does not support every backed-up section.');
    }
    await capture(); // Fresh preflight: fail before writing if settings cannot be read.
    if (radio.backupNodeNum != target) throw StateError('Connected radio changed.');
    await radio.writeBackup(snapshot);
    await radio.waitForBackupRadio(target);
    final owner = await radio.readOwner();
    if (owner.longName != snapshot.owner.longName || owner.shortName != snapshot.owner.shortName ||
        owner.isLicensed != snapshot.owner.isLicensed) throw StateError('Owner readback does not match.');
    for (final c in snapshot.configs) {
      if (await radio.readConfig(RadioBackupSnapshot.configType(c)) != c) {
        throw StateError('Configuration readback does not match.');
      }
    }
    for (final m in snapshot.modules) {
      if (await radio.readModuleConfig(RadioBackupSnapshot.moduleType(m)) != m) {
        throw StateError('Module readback does not match.');
      }
    }
    for (final c in snapshot.channels) {
      if (await radio.readChannel(c.index) != c) throw StateError('Channel readback does not match.');
    }
    if (radio.backupNodeNum != target) throw StateError('Connected radio changed.');
  }
}
