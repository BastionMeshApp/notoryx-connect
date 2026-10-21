import 'package:bastion/services/meshtastic_messaging_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bot replies carry the NOTORYX prefix', () {
    const away = MeshtasticMessagingService.defaultAwayReply;
    expect(away, startsWith('NOTORYX Connect '));
    expect(MeshtasticMessagingService.botResponse('!HELP ', away), 'NOTORYX: commands !help !status');
    expect(MeshtasticMessagingService.botResponse('!status', away), 'NOTORYX: online • radio READY');
    expect(MeshtasticMessagingService.botResponse('hello?', 'Back at 6'), 'NOTORYX: Back at 6');
  });

  test('replies from NOTORYX and older Bastion builds are never answered', () {
    for (final text in ['NOTORYX: online', ' notoryx: away', 'Bastion: commands !help', 'BASTION: x']) {
      expect(MeshtasticMessagingService.isBotReply(text), isTrue, reason: text);
    }
    for (final text in ['!help', 'notoryx is great', 'Bastion camp at 6']) {
      expect(MeshtasticMessagingService.isBotReply(text), isFalse, reason: text);
    }
  });

  test('the new prefix uses no more radio bytes than the old one', () {
    expect(MeshtasticMessagingService.botPrefix.length, 'Bastion:'.length);
  });
}
