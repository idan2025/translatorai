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
  const GlossaryEntry(this.terms, this.alone, {this.swaps = const {}, this.unless = const [], this.only = const []});

  /// When not empty, swaps apply only if one of these words is in the sentence
  /// too: מטען is a charger next to a phone, luggage next to a flight.
  final List<String> only;

  /// The Hebrew forms (singular, plural).
  final List<String> terms;

  /// The English when the term is said on its own.
  final String alone;

  /// Wrong English word → right one, applied inside a sentence that holds a term.
  final Map<String, String> swaps;

  /// Words that, said in the same sentence, mean the term is not the travel sense
  /// ("חשבון בנק" is a bank account): no swap then.
  final List<String> unless;
}

/// First names the model translates as words ("עידן" came out "Epoch"). Only
/// these are spoken as names after "קוראים לי" (my name is) or "שמי" (my name);
/// any other name is left to the model.
const hebrewNames = <String, String>{
  'עידן': 'Idan', 'דני': 'Dani', 'יוסי': 'Yossi', 'משה': 'Moshe', 'שרה': 'Sarah',
  'רונית': 'Ronit', 'נועה': 'Noa', 'תומר': 'Tomer', 'מיכל': 'Michal', 'דנה': 'Dana',
  'אורי': 'Uri', 'יעל': 'Yael', 'אלון': 'Alon', 'עומר': 'Omer', 'מאיה': 'Maya',
  'ליאור': 'Lior', 'רוני': 'Roni', 'אבי': 'Avi', 'שירה': 'Shira', 'רחל': 'Rachel',
  'דוד': 'David', 'יונתן': 'Yonatan', 'נועם': 'Noam', 'גיל': 'Gil', 'עדי': 'Adi',
};

final _nameIntro = RegExp(r'^(?:קוראים לי|שמי|השם שלי)\s+(\S+)$');

const hebrewEnglishGlossary = <GlossaryEntry>[
  GlossaryEntry(['כפית', 'כפיות'], 'teaspoon', swaps: {'spoons': 'teaspoons', 'spoon': 'teaspoon'}),
  GlossaryEntry(['חשבון'], 'bill',
      swaps: {'account': 'bill'},
      unless: ['בנק', 'משתמש', 'מייל', 'פייסבוק', 'גוגל', 'אינסטגרם', 'טוויטר', 'נטפליקס']), // "account" alone; "חשבון בנק" is a bank account
  // two senses: alone it stays the model's; next to a phone word it is a charger
  GlossaryEntry(['מטען', 'מטענים'], '',
      swaps: {'luggage': 'charger', 'cargo': 'charger', 'baggage': 'charger', 'load': 'charger'},
      only: ['טלפון', 'נייד', 'סלולרי', 'סוללה', 'טעינה', 'לטעון', 'להטעין', 'אייפון', 'USB', 'כבל', 'שקע', 'מחשב']),
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
  final intro = _nameIntro.firstMatch(s);
  if (intro != null && !please && hebrewNames.containsKey(intro.group(1))) {
    return 'My name is ${hebrewNames[intro.group(1)]}.';
  }
  for (final e in entries) {
    if (e.alone.isEmpty) continue; // no single travel sense
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
    if (e.unless.any(source.contains)) continue;
    if (e.only.isNotEmpty && !e.only.any(source.contains)) continue;
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

final _myNameIs = RegExp(r'\bmy name is ([A-Za-z]+)\b', caseSensitive: false);
final _shmiHu = RegExp(r'שמי (?:הוא|היא) ');

/// [translation] of English [source] into Hebrew, with the known fixes: Opus-MT
/// writes "My name is Idan" as "שמי הוא אידן" (a word-for-word "is", and the
/// name spelt from its sound). "שמי הוא" becomes "שמי", and a name from
/// [hebrewNames] gets its Hebrew spelling.
String applyHebrewGlossary(String source, String translation) {
  var out = translation.replaceAll(_shmiHu, 'שמי ');
  final m = _myNameIs.firstMatch(source);
  if (m != null) {
    final latin = m.group(1)!.toLowerCase();
    for (final e in hebrewNames.entries) {
      if (e.value.toLowerCase() != latin) continue;
      // the word after שמי is the model's spelling of the name
      out = out.replaceFirstMapped(RegExp(r'שמי (\S+?)([,.!?]|\s|$)'), (n) => 'שמי ${e.key}${n[2]}');
      break;
    }
  }
  return out;
}
