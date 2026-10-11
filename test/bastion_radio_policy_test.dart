import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/services/bastion_radio_policy.dart';

void main() {
  test('US notice uses effective preset bandwidth, not stale custom field', () {
    final config = Config_LoRaConfig(
      region: Config_LoRaConfig_RegionCode.US,
      usePreset: true,
      bandwidth: 500,
      modemPreset: Config_LoRaConfig_ModemPreset.LONG_FAST,
    );
    expect(BastionRadioPolicy.showUsNotice(config), isTrue);
    config.modemPreset = Config_LoRaConfig_ModemPreset.LONG_TURBO;
    config.bandwidth = 125;
    expect(BastionRadioPolicy.showUsNotice(config), isFalse);
    config.usePreset = false;
    expect(BastionRadioPolicy.showUsNotice(config), isTrue);
    config.region = Config_LoRaConfig_RegionCode.EU_868;
    expect(BastionRadioPolicy.showUsNotice(config), isFalse);
  });

  test('initial US setup changes draft only on verified firmware 2.8+', () {
    for (final version in ['2.8.0.abc', '2.10.1', '3.0.0']) {
      final draft = Config_LoRaConfig(
        region: Config_LoRaConfig_RegionCode.UNSET,
      );
      BastionRadioPolicy.chooseRegion(
        draft,
        Config_LoRaConfig_RegionCode.US,
        version,
      );
      expect(draft.modemPreset, Config_LoRaConfig_ModemPreset.LONG_TURBO);
      expect(draft.usePreset, isTrue);
    }
    for (final version in [null, '', 'unknown', '2.7.26']) {
      final draft = Config_LoRaConfig(
        region: Config_LoRaConfig_RegionCode.UNSET,
        modemPreset: Config_LoRaConfig_ModemPreset.MEDIUM_FAST,
      );
      BastionRadioPolicy.chooseRegion(
        draft,
        Config_LoRaConfig_RegionCode.US,
        version,
      );
      expect(draft.modemPreset, Config_LoRaConfig_ModemPreset.MEDIUM_FAST);
    }
  });

  test('existing configurations are preserved when selecting US', () {
    final draft = Config_LoRaConfig(
      region: Config_LoRaConfig_RegionCode.EU_868,
      usePreset: false,
      bandwidth: 125,
    );
    BastionRadioPolicy.chooseRegion(
      draft,
      Config_LoRaConfig_RegionCode.US,
      '2.8.0',
    );
    expect(draft.usePreset, isFalse);
    expect(draft.bandwidth, 125);
  });

  test('absent capability is not the same as a disabled LNA', () {
    expect(BastionRadioPolicy.canControlLna(Config_LoRaConfig()), isFalse);
    expect(
      BastionRadioPolicy.canControlLna(
        Config_LoRaConfig(
          femLnaMode: Config_LoRaConfig_FEM_LNA_Mode.NOT_PRESENT,
        ),
      ),
      isFalse,
    );
    expect(
      BastionRadioPolicy.canControlLna(
        Config_LoRaConfig(femLnaMode: Config_LoRaConfig_FEM_LNA_Mode.DISABLED),
      ),
      isTrue,
    );
  });
}
