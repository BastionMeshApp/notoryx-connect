import 'package:bastion/radio_settings_page.dart';
import 'package:bastion/generated/meshtastic/admin.pb.dart';
import 'package:bastion/generated/meshtastic/module_config.pb.dart';
import 'package:bastion/services/meshtastic_admin_session.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class UnavailableRadio extends MeshtasticRadioCoordinator {
  @override bool get canAdminister => true;
  @override Future<ModuleConfig> readModuleConfig(AdminMessage_ModuleConfigType type) async =>
      throw MeshtasticSettingsUnavailable(type.name);
}

void main() {
  testWidgets('unavailable settings stay read-only and clear of system navigation', (tester) async {
    final radio = UnavailableRadio();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(bottom: 48)),
      child: child!), home: RadioSettingsPage(radio: radio)));
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Mesh Beacon'), 500, scrollable: list);
    await tester.tap(find.text('Mesh Beacon'));
    await tester.pumpAndSettle();
    expect(find.text('Mesh Beacon settings are unavailable through this radio’s firmware API.'), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
    final save = tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE'));
    expect(save.onPressed, isNull);
    expect(tester.getBottomRight(find.byType(ListView)).dy,
        lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio - 48));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('abbreviated module names have readable titles', (tester) async {
    final radio = MeshtasticRadioCoordinator();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: RadioSettingsPage(radio: radio)));
    for (final title in ['Device UI', 'MQTT', 'External notifications',
        'Canned messages', 'Remote hardware', 'TAK', 'Mesh Beacon']) {
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(find.text(title), 150, scrollable: find.byType(Scrollable).first);
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('radio settings are locked until a radio is ready', (tester) async {
    final radio = MeshtasticRadioCoordinator();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: RadioSettingsPage(radio: radio)));

    expect(find.text('Radio not ready'), findsOneWidget);
    for (final title in ['Owner', 'LoRa', 'Channels', 'Device', 'Position']) {
      final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, title));
      expect(tile.enabled, isFalse, reason: title);
    }

    await tester.tap(find.text('LoRa'));
    await tester.pumpAndSettle();
    expect(find.text('Radio settings'), findsOneWidget);
  });
}
