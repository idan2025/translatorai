import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

/// Which language a piece of text is in, decided in two steps: the alphabet
/// first (exact: Cyrillic is never Polish, Hebrew letters are never Arabic),
/// then a text language identifier among the languages that alphabet allows.
/// In a conversation only the two chosen languages are ever answered.

enum Script { latin, cyrillic, greek, hebrew, arabic, devanagari, bengali, gujarati, tamil, telugu, kannada, thai, georgian, hangul, kana, han, other }

const _ranges = <Script, List<List<int>>>{
  Script.latin: [[0x41, 0x5A], [0x61, 0x7A], [0xC0, 0x24F], [0x1E00, 0x1EFF]],
  Script.cyrillic: [[0x400, 0x52F]],
  Script.greek: [[0x370, 0x3FF], [0x1F00, 0x1FFF]],
  Script.hebrew: [[0x590, 0x5FF]],
  Script.arabic: [[0x600, 0x6FF], [0x750, 0x77F], [0xFB50, 0xFDFF], [0xFE70, 0xFEFF]],
  Script.devanagari: [[0x900, 0x97F]],
  Script.bengali: [[0x980, 0x9FF]],
  Script.gujarati: [[0xA80, 0xAFF]],
  Script.tamil: [[0xB80, 0xBFF]],
  Script.telugu: [[0xC00, 0xC7F]],
  Script.kannada: [[0xC80, 0xCFF]],
  Script.thai: [[0xE00, 0xE7F]],
  Script.georgian: [[0x10A0, 0x10FF]],
  Script.hangul: [[0xAC00, 0xD7AF], [0x1100, 0x11FF], [0x3130, 0x318F]],
  Script.kana: [[0x3040, 0x30FF]],
  Script.han: [[0x4E00, 0x9FFF], [0x3400, 0x4DBF]],
};

/// Languages written in each non-Latin script. Every other language is Latin.
const scriptLanguages = <Script, Set<String>>{
  Script.cyrillic: {'ru', 'uk', 'bg', 'be', 'mk', 'sr', 'kk', 'mn', 'tg', 'ky', 'tt', 'ba'},
  Script.greek: {'el'},
  Script.hebrew: {'he', 'yi'},
  Script.arabic: {'ar', 'fa', 'ur', 'ps', 'sd', 'ug'},
  Script.devanagari: {'hi', 'mr', 'ne', 'sa'},
  Script.bengali: {'bn', 'as'},
  Script.gujarati: {'gu'},
  Script.tamil: {'ta'},
  Script.telugu: {'te'},
  Script.kannada: {'kn'},
  Script.thai: {'th'},
  Script.georgian: {'ka'},
  Script.hangul: {'ko'},
  Script.kana: {'ja'},
  Script.han: {'zh', 'ja'},
};

/// The most-spoken language of each shared script: the answer when the text
/// identifier has nothing to say about a short phrase.
const scriptDefault = <Script, String>{
  Script.cyrillic: 'ru', Script.hebrew: 'he', Script.arabic: 'ar', Script.devanagari: 'hi',
  Script.bengali: 'bn', Script.han: 'zh',
};

final Set<String> _nonLatin = {for (final s in scriptLanguages.values) ...s};

Script scriptOfChar(int c) {
  for (final e in _ranges.entries) {
    for (final r in e.value) {
      if (c >= r[0] && c <= r[1]) return e.key;
    }
  }
  return Script.other;
}

/// The script most of the letters are in. Any kana makes Han text Japanese.
Script scriptOf(String text) {
  final counts = <Script, int>{};
  for (final c in text.runes) {
    final s = scriptOfChar(c);
    if (s != Script.other) counts[s] = (counts[s] ?? 0) + 1;
  }
  if (counts.isEmpty) return Script.other;
  if ((counts[Script.kana] ?? 0) > 0 && (counts[Script.han] ?? 0) + (counts[Script.kana] ?? 0) >= counts.values.reduce((a, b) => a > b ? a : b)) {
    return Script.kana;
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// Whether [code] is written in [script].
bool writtenIn(String code, Script script) {
  if (script == Script.other) return true;
  if (script == Script.latin) return !_nonLatin.contains(code);
  return scriptLanguages[script]!.contains(code);
}

/// ML Kit's tags into the codes the rest of the app uses.
String normaliseTag(String tag) {
  final base = tag.split('-').first.toLowerCase();
  return const {'iw': 'he', 'fil': 'tl', 'nb': 'no', 'nn': 'no', 'in': 'id', 'ji': 'yi'}[base] ?? base;
}

class Guess {
  const Guess(this.code, this.confidence);
  final String code;
  final double confidence;
}

/// Ranks languages for a text, best first. Abstract so tests need no phone.
abstract class TextLanguageGuesser {
  Future<List<Guess>> guess(String text);
  Future<void> close() async {}
}

class MlKitGuesser extends TextLanguageGuesser {
  final _id = LanguageIdentifier(confidenceThreshold: 0.01);

  @override
  Future<List<Guess>> guess(String text) async {
    final out = await _id.identifyPossibleLanguages(text);
    return [
      for (final l in out)
        if (l.languageTag != 'und') Guess(normaliseTag(l.languageTag), l.confidence),
    ];
  }

  @override
  Future<void> close() => _id.close();
}

/// The language of [text], or null when it cannot be told.
///
/// [among]: only these may be answered (a conversation's two languages). A
/// text whose alphabet fits none of them gives null. [prefer] breaks a tie
/// the identifier leaves open (the side that did not speak last).
Future<String?> identify(String text, TextLanguageGuesser guesser, {Set<String>? among, String? prefer}) async {
  final script = scriptOf(text);
  if (among != null) {
    final fits = among.where((c) => writtenIn(c, script)).toList();
    if (fits.isEmpty) return null;
    if (fits.length == 1) return fits.single;
    final guesses = await guesser.guess(text);
    for (final g in guesses) {
      if (fits.contains(g.code)) return g.code;
    }
    return prefer != null && fits.contains(prefer) ? prefer : fits.first;
  }
  final only = script == Script.latin || script == Script.other ? null : scriptLanguages[script]!;
  if (only != null && only.length == 1) return only.single;
  final guesses = await guesser.guess(text);
  for (final g in guesses) {
    if (writtenIn(g.code, script)) return g.code;
  }
  return scriptDefault[script];
}
