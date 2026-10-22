import 'package:bastion/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('the dark theme uses the icon orange exactly', () {
    expect(BastionApp.appearance(Brightness.dark).colorScheme.primary, const Color(0xFFFC7202));
  });

  for (final brightness in Brightness.values) {
    test('${brightness.name} theme accent meets WCAG AA contrast', () {
      final theme = BastionApp.appearance(brightness);
      final scheme = theme.colorScheme;
      final surfaces = {
        'scaffold': theme.scaffoldBackgroundColor,
        'card': theme.cardTheme.color!,
        'surface': scheme.surface,
      };
      for (final MapEntry(:key, :value) in surfaces.entries) {
        expect(contrast(scheme.primary, value), greaterThanOrEqualTo(4.5),
            reason: 'accent text on $key');
      }
      expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5),
          reason: 'text on filled accent buttons');
    });
  }

  testWidgets('icon tints follow the theme', (tester) async {
    Future<Color> accentIn(Brightness brightness) async {
      late Color accent;
      await tester.pumpWidget(Theme(data: BastionApp.appearance(brightness),
          child: Builder(builder: (c) { accent = BastionApp.accentOf(c); return const SizedBox(); })));
      return accent;
    }
    final dark = await accentIn(Brightness.dark);
    final light = await accentIn(Brightness.light);
    expect(dark, BastionApp.signal);
    expect(light, BastionApp.signalOnLight);
  });
}
