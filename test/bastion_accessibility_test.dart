import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:bastion/main.dart';
import 'package:bastion/field_tools_page.dart';
import 'package:bastion/services/bastion_preferences.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CI'] != 'true') return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/field-qa/$name.png'); await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List()); image.dispose();
  });
}

class TemplateRadio extends MeshtasticRadioCoordinator {
  bool ready = true;
  final sent = <String>[];
  @override bool get isReady => ready;
  @override int? get localNodeNum => 42;
  @override List<({int index, int role, String name})> get channelMetadata => [(index: 0, role: 1, name: 'Field')];
  @override Future<int> sendText({required String text, int destination = 0xffffffff, int channel = 0}) async { sent.add('$channel:$text'); return 1; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final cache = Directory.systemTemp.createTempSync('bastion-widget-map-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => cache.path);
  });
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('shell fits narrow screen with large text in ${mode.name} theme', (tester) async {
      tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await BastionPreferences.instance.update(mode: mode);
      final capture = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: capture, child: const BastionApp())); await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.settings_outlined).last); await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Appearance & dashboard'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Appearance & dashboard')); await tester.pumpAndSettle();
      expect(find.text('Dashboard statistics'), findsOneWidget);
      await screenshot(tester, capture, '${mode.name}-large-settings');
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

  testWidgets('template send needs explicit confirmation and cannot queue after disconnect', (tester) async {
    final radio = TemplateRadio(); addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: FieldToolsPage(radio: radio)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Emergency & check-in templates'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Emergency & check-in templates')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review message'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Review message')); await tester.pumpAndSettle();
    await tester.tap(find.text('Review message')); await tester.pumpAndSettle();
    expect(radio.sent, isEmpty);
    radio.ready = false;
    await tester.tap(find.text('Send message')); await tester.pumpAndSettle();
    expect(radio.sent, isEmpty);
    radio.ready = true; radio.notifyListeners(); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review message')); await tester.pumpAndSettle();
    await tester.tap(find.text('Review message')); await tester.pumpAndSettle();
    await tester.tap(find.text('Send message')); await tester.pumpAndSettle();
    expect(radio.sent, hasLength(1)); expect(radio.sent.single, startsWith('0:ASSISTANCE REQUESTED'));
    expect(tester.takeException(), isNull);
  });

}
