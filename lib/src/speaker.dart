import 'package:flutter_tts/flutter_tts.dart';

/// Reads a translation aloud with the phone's own text-to-speech, which is
/// on-device and plays through whatever is connected: speaker, wired or
/// Bluetooth earbuds. No special headset needed.
class Speaker {
  Speaker() {
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts = FlutterTts();
  String? _lang;

  /// Speaks [text] in [code] and completes when it has finished.
  /// Returns false when the phone has no voice for that language.
  Future<bool> say(String text, String code) async {
    if (_lang != code) {
      final ok = await _tts.isLanguageAvailable(code);
      if (ok != true) return false;
      await _tts.setLanguage(code);
      _lang = code;
    }
    await _tts.speak(text);
    return true;
  }

  Future<void> stop() => _tts.stop();
}
