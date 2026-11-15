import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Reads a translation aloud with the phone's own text-to-speech, which is
/// on-device and plays through whatever is connected: speaker, wired or
/// Bluetooth earbuds. No special headset needed.
class Speaker {
  Speaker() {
    _tts.awaitSpeakCompletion(true);
    // The completion callback is the reliable "finished": speak() itself can
    // return early on some engines, and the microphone must stay closed until
    // the voice has really stopped, or it hears the translation as new speech.
    _tts.setCompletionHandler(_finish);
    _tts.setCancelHandler(_finish);
    _tts.setErrorHandler((_) => _finish());
  }

  final FlutterTts _tts = FlutterTts();
  String? _lang;
  Completer<void>? _done;

  void _finish() {
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
  }

  /// Gets the voice for [code] ready before it is needed: the first word
  /// otherwise waits for the engine to start.
  Future<void> warm(String code) async {
    try {
      if (_lang != code && await _tts.isLanguageAvailable(code) == true) {
        await _tts.setLanguage(code);
        _lang = code;
      }
    } catch (_) {}
  }

  /// Speaks [text] in [code] and completes when the voice has stopped.
  /// Returns false when the phone has no voice for that language.
  Future<bool> say(String text, String code) async {
    if (_lang != code) {
      final ok = await _tts.isLanguageAvailable(code);
      if (ok != true) return false;
      await _tts.setLanguage(code);
      _lang = code;
    }
    final done = _done = Completer<void>();
    await _tts.speak(text);
    // never wait forever if an engine never reports back: ~10 characters a second, plus slack
    await done.future.timeout(Duration(seconds: 3 + text.length ~/ 8), onTimeout: () {});
    return true;
  }

  Future<void> stop() async {
    await _tts.stop();
    _finish();
  }
}
