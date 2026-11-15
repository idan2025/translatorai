import 'asr.dart';
import 'pipeline.dart';

/// Whether [text] ends a sentence (full stop, question or exclamation mark,
/// ellipsis, in Latin, CJK or Arabic punctuation, possibly closed by a quote).
bool endsSentence(String text) => RegExp(r'[.!?…。！？؟]["”’»)\]]*\s*$').hasMatch(text.trim());

/// Joins two pieces of one thought. Chinese, Japanese and Thai are written
/// without spaces between words.
String joinText(String a, String b, String language) {
  const noSpace = {'zh', 'ja', 'th', 'lo', 'km', 'my'};
  final left = a.trimRight(), right = b.trimLeft();
  return noSpace.contains(language) ? '$left$right' : '$left $right';
}

/// A pause inside a sentence splits it in two, and each half translates worse
/// alone ("Where is the" / "new store till?"). The joiner holds a piece that
/// does not end a sentence for a moment and joins the next piece of the same
/// direction to it. Pure: the caller supplies the clock.
class SentenceJoiner {
  SentenceJoiner({this.window = const Duration(milliseconds: 1200), this.maxHold = const Duration(seconds: 8)});

  /// How long to wait for the rest of a sentence after a piece.
  final Duration window;

  /// A thought is let go after this long however it ends.
  final Duration maxHold;

  Heard? _heard;
  Direction? _dir;
  DateTime? _first, _last;

  bool get holding => _heard != null;

  /// What is being held, for showing while it waits for the rest of its sentence.
  String get heldText => _heard?.text ?? '';

  /// When the held piece should be let go if nothing else arrives, or null.
  DateTime? get dueAt => _last?.add(window);

  /// A new piece. Returns what is ready to go now (zero, one or two pieces).
  List<(Heard, Direction)> offer(Heard h, Direction d, DateTime now) {
    final out = <(Heard, Direction)>[];
    final held = _heard;
    if (held != null && _dir == d && !endsSentence(held.text) && now.difference(_first!) < maxHold) {
      _heard = Heard(joinText(held.text, h.text, h.language), held.seconds + h.seconds, held.decodeMs + h.decodeMs,
          language: h.language, forced: h.forced);
    } else {
      out.addAll(flush());
      _heard = h;
      _dir = d;
      _first = now;
    }
    _last = now;
    if (endsSentence(_heard!.text) || now.difference(_first!) >= maxHold) out.addAll(flush());
    return out;
  }

  /// The held piece, if it has waited long enough with nothing joining it.
  List<(Heard, Direction)> due(DateTime now) => _last != null && !now.isBefore(_last!.add(window)) ? flush() : const [];

  /// Lets go of whatever is held, now (the person stopped, or switched side).
  List<(Heard, Direction)> flush() {
    final h = _heard;
    if (h == null) return const [];
    final d = _dir!;
    _heard = null;
    _dir = null;
    _first = _last = null;
    return [(h, d)];
  }
}
