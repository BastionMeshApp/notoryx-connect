import 'package:bastion/main.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ChannelRadio extends MeshtasticRadioCoordinator {
  int? sentChannel;
  bool disconnected = false;
  @override List<({int index, int role, String name})> get channelMetadata => disconnected ? [] : [
    (index: 0, role: 1, name: 'Main'), (index: 2, role: 2, name: 'Field'),
    (index: 3, role: 0, name: 'Disabled')];
  @override Future<int> sendText({required String text, int destination = 0xffffffff, int channel = 0}) async {
    sentChannel = channel;
    return 7;
  }
}
void main() {
  testWidgets('selected secondary channel is used for a broadcast', (tester) async {
    final radio = ChannelRadio();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BastionChatsPage(
      radio: radio, botMode: false, awayReply: '', onBotModeChanged: (_) {}, onAwayReplyChanged: (_) {}))));
    await tester.tap(find.text('Channel 0 • Main'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 3 • Disabled'), findsNothing);
    await tester.tap(find.text('Channel 2 • Field').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Message Channel 2'), 'secondary test');
    await tester.ensureVisible(find.text('SEND'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SEND'));
    await tester.pumpAndSettle();
    expect(radio.sentChannel, 2);
    radio.disconnected = true;
    radio.notifyListeners();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Channel 2 • Offline'), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Channel 2 • Offline'), findsOneWidget);
  });
}
