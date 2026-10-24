// Renders README screenshots of each main tab and the main sub-screens
// with real fonts.
// Skipped unless PREVIEW_OUT is set:
//   PREVIEW_OUT=docs/screenshots flutter test test/preview
// No radio is connected, so tabs show their not-yet-connected state.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bastion/beacon_page.dart';
import 'package:bastion/field_tools_page.dart';
import 'package:bastion/main.dart';
import 'package:bastion/phone_backup_page.dart';
import 'package:bastion/privacy_page.dart';
import 'package:bastion/radio_backup_page.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:bastion/trip_page.dart';
import 'package:bastion/services/bastion_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  final fonts = '${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts';
  await load('Roboto', [
    for (final w in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) '$fonts/Roboto-$w.ttf',
  ]);
  await load('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['PREVIEW_OUT'];
  // Tab icon to tap, and the file name for that tab.
  final tabs = {
    Icons.shield_outlined: 'home',
    Icons.hub_outlined: 'nodes',
    Icons.chat_bubble_outline: 'chats',
    Icons.build_outlined: 'tools',
    Icons.settings_outlined: 'settings',
  };

  setUpAll(() async {
    if (out != null) await _loadFonts();
  });

  // The map tab is built off-screen and asks for a tile cache directory;
  // the message archive needs a working store.
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final tmp = Directory.systemTemp.createTempSync('preview').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tmp);
  });

  // Sub-screens opened from the tabs, rendered in the dark theme.
  final pages = <String, Widget Function(MeshtasticRadioCoordinator)>{
    'field_records': (radio) => FieldToolsPage(radio: radio),
    'privacy': (radio) => PrivacyPage(radio: radio),
    'radio_backup': (radio) => RadioBackupPage(radio: radio),
    'phone_backup': (radio) => PhoneBackupPage(radio: radio),
    'beacons': (radio) => BeaconPage(radio: radio),
    'trip': (radio) => TripPage(radio: radio),
  };
  for (final page in pages.entries) {
    testWidgets('page ${page.key}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final radio = MeshtasticRadioCoordinator();
      addTearDown(radio.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BastionApp.appearance(Brightness.dark),
        home: page.value(radio),
      )));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await ro.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/${page.key}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    }, skip: out == null);
  }

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('main tabs ${mode.name}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      BastionPreferences.instance.theme = mode;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: const BastionApp()));
      await tester.pumpAndSettle();
      for (final tab in tabs.entries) {
        await tester.tap(find.byIcon(tab.key).last);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final suffix = mode == ThemeMode.dark ? '' : '_light';
          File('$out/${tab.value}$suffix.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    }, skip: out == null);
  }
}
