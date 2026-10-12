import 'dart:typed_data';
import 'package:protobuf/protobuf.dart';
import '../generated/meshtastic/config.pb.dart';
import '../generated/meshtastic/module_config.pb.dart';

/// Startup advertisements prove presence, while omission proves nothing.
abstract final class BastionSettingsEvidence {
  static String? advertisedKey(Uint8List bytes, {required bool module}) {
    try {
      if (module) {
        final variant = ModuleConfig.fromBuffer(bytes).whichPayloadVariant();
        return variant == ModuleConfig_PayloadVariant.notSet ? null : 'module:${variant.index}';
      }
      final variant = Config.fromBuffer(bytes).whichPayloadVariant();
      return variant == Config_PayloadVariant.notSet ? null : 'config:${variant.index}';
    } on InvalidProtocolBufferException { return null; }
  }
}
