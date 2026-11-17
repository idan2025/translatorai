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
  String? _voiceKey;

  /// Each voice's own locale tag (`en-US`): the engine matches a voice by name *and* that exact tag.
  final _locales = <String, String>{};
  Completer<void>? _done;

  /// The voice the person picked for a language, by name, or null for the phone's default.
  /// Read on every sentence, so a change in Settings applies at once.
  String? Function(String code) preferred = (_) => null;

  void _finish() {
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
  }

  /// The phone's voices for [code] (e.g. `he`, `en`), by name. Empty when none is installed.
  Future<List<String>> voices(String code) async {
    try {
      final all = await _tts.getVoices;
      if (all is! List) return const [];
      final names = <String>{};
      for (final v in all) {
        if (v is! Map) continue;
        final raw = '${v['locale'] ?? ''}';
        final locale = raw.replaceAll('_', '-').toLowerCase();
        final name = '${v['name'] ?? ''}';
        if (name.isEmpty) continue;
        _locales[name] = raw;
        if (locale == code || locale.startsWith('$code-')) names.add(name);
      }
      return names.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  /// Makes [code]'s language and the picked voice ready. False when the phone has no voice for [code].
  Future<bool> _ready(String code) async {
    if (_lang != code) {
      final ok = await _tts.isLanguageAvailable(code);
      if (ok != true) return false;
      await _tts.setLanguage(code);
      _lang = code;
      _voiceKey = null;
    }
    final pick = preferred(code);
    final key = '$code|${pick ?? ''}';
    if (_voiceKey != key) {
      try {
        if (pick != null && pick.isNotEmpty) {
          if (!_locales.containsKey(pick)) await voices(code);
          await _tts.setVoice({'name': pick, 'locale': _locales[pick] ?? code});
        } else {
          await _tts.setLanguage(code); // back to the language's default voice
        }
      } catch (_) {}
      _voiceKey = key;
    }
    return true;
  }

  /// Gets the voice for [code] ready before it is needed: the first word
  /// otherwise waits for the engine to start.
  Future<void> warm(String code) async {
    try {
      await _ready(code);
    } catch (_) {}
  }

  /// Speaks [text] in [code] and completes when the voice has stopped.
  /// Returns false when the phone has no voice for that language.
  Future<bool> say(String text, String code) async {
    if (!await _ready(code)) return false;
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
