import 'dart:typed_data';
import 'package:bastion/services/bastion_settings_evidence.dart';
import 'package:bastion/generated/meshtastic/admin.pb.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/generated/meshtastic/module_config.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('absent or malformed advertisements never imply unsupported firmware', () {
    expect(BastionSettingsEvidence.advertisedKey(Config().writeToBuffer(), module: false), isNull);
    expect(BastionSettingsEvidence.advertisedKey(ModuleConfig().writeToBuffer(), module: true), isNull);
    expect(BastionSettingsEvidence.advertisedKey(Uint8List.fromList([255]), module: true), isNull);
  });
  test('default-value advertised sections retain their correct admin index', () {
    expect(BastionSettingsEvidence.advertisedKey(Config(device: Config_DeviceConfig()).writeToBuffer(), module: false), 'config:${AdminMessage_ConfigType.DEVICE_CONFIG.value}');
    expect(BastionSettingsEvidence.advertisedKey(Config(lora: Config_LoRaConfig()).writeToBuffer(), module: false), 'config:${AdminMessage_ConfigType.LORA_CONFIG.value}');
    expect(BastionSettingsEvidence.advertisedKey(ModuleConfig(mqtt: ModuleConfig_MQTTConfig()).writeToBuffer(), module: true), 'module:${AdminMessage_ModuleConfigType.MQTT_CONFIG.value}');
    expect(BastionSettingsEvidence.advertisedKey(ModuleConfig(tak: ModuleConfig_TAKConfig()).writeToBuffer(), module: true), 'module:${AdminMessage_ModuleConfigType.TAK_CONFIG.value}');
    expect(BastionSettingsEvidence.advertisedKey(ModuleConfig(meshBeacon: ModuleConfig_MeshBeaconConfig()).writeToBuffer(), module: true), 'module:${AdminMessage_ModuleConfigType.MESHBEACON_CONFIG.value}');
  });
}
