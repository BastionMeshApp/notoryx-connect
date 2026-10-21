import 'package:bastion/services/bastion_background_service.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _NoopKeeper implements BastionBackgroundKeeper {
  @override
  Future<void> keepAlive({required String radioName, required bool reconnecting}) async {}

  @override
  Future<void> release() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  test('low-power field mode is off by default and survives a restart', () async {
    final first = MeshtasticRadioCoordinator(background: _NoopKeeper());
    await pumpEventQueue();
    expect(first.lowPowerMode, isFalse);
    await first.setLowPowerMode(true);
    expect(first.lowPowerMode, isTrue);
    first.dispose();

    final second = MeshtasticRadioCoordinator(background: _NoopKeeper());
    await pumpEventQueue();
    expect(second.lowPowerMode, isTrue);
    second.dispose();
  });
}
