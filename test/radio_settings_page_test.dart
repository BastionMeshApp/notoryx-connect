import 'package:bastion/radio_settings_page.dart';
import 'package:bastion/generated/meshtastic/admin.pb.dart';
import 'package:bastion/generated/meshtastic/mesh.pb.dart' show User;
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

class SaveVerificationRadio extends MeshtasticRadioCoordinator {
  SaveVerificationRadio({required this.apply});
  final bool apply;
  int reads = 0, writes = 0;
  User owner = User(longName: 'Trail', shortName: 'TR');
  @override bool get canAdminister => true;
  @override int? get localNodeNum => 42;
  @override Future<User> readOwner() async { reads++; return owner.deepCopy(); }
  @override Future<void> writeOwner(User value) async { writes++; if (apply) owner = value.deepCopy(); }
  @override Future<void> waitForBackupRadio(int node) async {}
}

void main() {
  for (final applied in [true, false]) {
    testWidgets('owner save closes only after matching fresh read: $applied', (tester) async {
      final radio = SaveVerificationRadio(apply: applied); addTearDown(radio.dispose);
      await tester.pumpWidget(MaterialApp(home: RadioSettingsPage(radio: radio)));
      await tester.tap(find.text('Owner')); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Trail Updated'); await tester.pump();
      await tester.tap(find.text('SAVE')); await tester.pumpAndSettle();
      await tester.tap(find.text('Save')); await tester.pumpAndSettle();
      expect(radio.writes, 1); expect(radio.reads, 2);
      if (applied) {
        expect(find.text('Owner saved and verified from radio.'), findsOneWidget);
        expect(find.text('Radio settings'), findsOneWidget);
      } else {
        expect(find.textContaining('Save not verified:'), findsOneWidget);
        expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE')).onPressed, isNull);
        await tester.tap(find.text('Reload from radio')); await tester.pumpAndSettle();
        expect(radio.writes, 1); expect(radio.reads, 3);
      }
      expect(tester.takeException(), isNull);
    });
  }

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
