import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads text aloud; faked in tests.
abstract interface class BastionSpeaker {
  Future<void> speak(String text);
}

/// The phone's text-to-speech engine. Failures are ignored: reading aloud is
/// a convenience, never needed to receive a message.
class TtsSpeaker implements BastionSpeaker {
  FlutterTts? _tts;

  @override
  Future<void> speak(String text) async {
    try {
      final tts = _tts ??= FlutterTts()..awaitSpeakCompletion(true);
      await tts.speak(text);
    } catch (error) {
      debugPrint('Read aloud failed: $error');
    }
  }
}
