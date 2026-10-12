import 'package:bastion/radio_backup_page.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('backup requires a strong password before reading radio settings', (tester) async {
    final radio = MeshtasticRadioCoordinator();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: RadioBackupPage(radio: radio)));
    await tester.enterText(find.widgetWithText(TextField, 'Backup password (at least 12 characters)'), 'short');
    await tester.tap(find.text('Create encrypted backup'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters for the backup password.'), findsOneWidget);
    final password = tester.widget<TextField>(find.widgetWithText(TextField, 'Backup password (at least 12 characters)'));
    expect(password.controller!.text, isEmpty);
  });
}
