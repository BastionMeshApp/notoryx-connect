import 'package:bastion/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('message history search includes queued messages', (tester) async {
    await tester.pumpWidget(const BastionApp());
    await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
    await tester.pumpAndSettle();
    final composer = find.widgetWithText(TextField, 'Message Channel 0');
    await tester.enterText(composer, 'field check alpha');
    await tester.tap(find.text('SEND'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Search message history'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, 'Search message history'), 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('field check alpha'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Search message history'), 'unmatched');
    await tester.pumpAndSettle();
    expect(find.text('field check alpha'), findsNothing);
    expect(find.text('No messages match your search.'), findsOneWidget);
  });
}
