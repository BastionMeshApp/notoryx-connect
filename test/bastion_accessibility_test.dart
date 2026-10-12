import 'package:bastion/main.dart';
import 'package:bastion/field_tools_page.dart';
import 'package:bastion/services/bastion_preferences.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('shell fits narrow screen with large text in ${mode.name} theme', (tester) async {
      tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await BastionPreferences.instance.update(mode: mode);
      await tester.pumpWidget(const BastionApp()); await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.settings_outlined).last); await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Appearance & dashboard'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Appearance & dashboard')); await tester.pumpAndSettle();
      expect(find.text('Dashboard statistics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('offline templates cannot transmit and field screen fits large text', (tester) async {
    final radio = MeshtasticRadioCoordinator(); addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
      home: FieldToolsPage(radio: radio)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Emergency & check-in templates'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Emergency & check-in templates')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review message'), 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Review message')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
