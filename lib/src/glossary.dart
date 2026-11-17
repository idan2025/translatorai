/// Corrections for words a translation model is known to get wrong, found by
/// running travel vocabulary through it (Opus-MT Hebrew → English, 2026-11-17:
/// 9 of 130 travel words wrong on their own, almost all right inside a sentence).
///
/// Two kinds, both conservative:
/// - **Said alone**: the whole utterance is the term (with "the" or "please"
///   around it): "כפית" → "Teaspoon", "החשבון, בבקשה" → "The bill, please".
///   A lone word is where the model has no context to pick the sense.
/// - **Inside a sentence**: only where the source word has one meaning and the
///   model writes another, and only by swapping that word back: כפית is always
///   a teaspoon, so "spoon" becomes "teaspoon" when כפית was said and
///   "teaspoon" is not in the translation already.
class GlossaryEntry {
  const GlossaryEntry(this.terms, this.alone, {this.swaps = const {}});

  /// The Hebrew forms (singular, plural).
  final List<String> terms;

  /// The English when the term is said on its own.
  final String alone;

  /// Wrong English word → right one, applied inside a sentence that holds a term.
  final Map<String, String> swaps;
}

const hebrewEnglishGlossary = <GlossaryEntry>[
  GlossaryEntry(['כפית', 'כפיות'], 'teaspoon', swaps: {'spoons': 'teaspoons', 'spoon': 'teaspoon'}),
  GlossaryEntry(['חשבון'], 'bill'), // "account" alone; "חשבון בנק" is a bank account, so no swap
  GlossaryEntry(['עודף'], 'change'), // "excess" alone; "עודף משקל" is excess weight
  GlossaryEntry(['קבלה'], 'receipt'), // "acceptance" alone
  GlossaryEntry(['מפתח'], 'key'), // "developer" alone
  GlossaryEntry(['שירותים'], 'restroom'), // "services" alone
  GlossaryEntry(['כניסה'], 'entrance'), // "login" alone
  GlossaryEntry(['כרטיס הלוך חזור', 'כרטיס הלוך ושוב'], 'round-trip ticket'), // "ticket back"
  GlossaryEntry(['מעבר חציה', 'מעבר חצייה'], 'crosswalk'), // "crossing pass"
];

const _letters = 'א-ת';
final _please = RegExp(r'[\s,]*בבקשה[\s.!?]*$');
final _edges = RegExp(r'^[\s"״׳.,!?־-]+|[\s"״׳.,!?־-]+$');

/// [translation] of Hebrew [source] into English, with the glossary applied.
String applyGlossary(String source, String translation, {List<GlossaryEntry> entries = hebrewEnglishGlossary}) {
  var s = source.trim();
  final please = _please.hasMatch(s);
  if (please) s = s.replaceFirst(_please, '');
  s = s.replaceAll(_edges, '');
  for (final e in entries) {
    for (final t in e.terms) {
      final definite = s == 'ה$t' || (t.contains(' ') && s == 'ה${t.replaceFirst(' ', ' ה')}');
      if (s == t || definite) {
        final text = '${definite ? 'the ' : ''}${e.alone}';
        return '${text[0].toUpperCase()}${text.substring(1)}${please ? ', please.' : ''}';
      }
    }
  }
  var out = translation;
  for (final e in entries) {
    if (e.swaps.isEmpty) continue;
    final said = e.terms.any((t) => RegExp('(?<![$_letters])[והבלמשכ]{0,3}${RegExp.escape(t)}(?![$_letters])').hasMatch(source));
    if (!said) continue;
    for (final w in e.swaps.entries) {
      if (RegExp('\\b${RegExp.escape(w.value)}\\b', caseSensitive: false).hasMatch(out)) continue; // already right
      out = out.replaceAllMapped(RegExp('\\b${RegExp.escape(w.key)}\\b', caseSensitive: false), (m) {
        final hit = m[0]!;
        return hit[0] == hit[0].toUpperCase() ? '${w.value[0].toUpperCase()}${w.value.substring(1)}' : w.value;
      });
    }
  }
  return out;
}
