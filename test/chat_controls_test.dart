import 'package:bastion/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  testWidgets('message history search includes queued messages', (tester) async {
    await tester.pumpWidget(const BastionApp());
    await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
    await tester.pumpAndSettle();
    final composer = find.widgetWithText(TextField, 'Message Channel 0');
    await tester.enterText(composer, 'field check alpha');
    await tester.ensureVisible(find.text('SEND'));
    await tester.pumpAndSettle();
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

  testWidgets('Chats warns when message history cannot be read', (tester) async {
    SharedPreferencesAsyncPlatform.instance = _UnreadableStore();
    await tester.pumpWidget(const BastionApp());
    await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('Message storage problem'), findsOneWidget);
    expect(find.textContaining('stored history is not overwritten'), findsOneWidget);
  });
}

final class _UnreadableStore extends InMemorySharedPreferencesAsync {
  _UnreadableStore() : super.empty();
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async {
    if (key == 'bastion.comms.archive.v1') throw StateError('read failed');
    return super.getString(key, options);
  }
}
