import 'words.dart';

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
  if (s.isEmpty && please) return 'Please.';
  final word = _wordAlone(s);
  if (word != null) return '${word[0].toUpperCase()}${word.substring(1)}${please ? ', please.' : ''}';
  var out = _collapseRepeats(translation, source);
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

/// The word from [hebrewWords] when [s] is exactly one ("מטוס", "המטוס" → "the airplane").
String? _wordAlone(String s) {
  s = s.replaceAll(RegExp('[\'׳`]'), '');
  final plain = hebrewWords[s];
  if (plain != null) return plain;
  if (s.startsWith('ה')) {
    final w = hebrewWords[s.substring(1)];
    if (w != null) return 'the $w';
  }
  return null;
}

/// A short utterance the model answers with a stutter ("Flight Flight Flight", "Water and
/// Water"): the repeat is dropped. Only for sources of up to three words.
String _collapseRepeats(String out, String source) {
  if (source.trim().split(RegExp(r'\s+')).length > 3) return out;
  var t = out;
  t = t.replaceAllMapped(RegExp(r'\b(\w[\w\x27-]*)(?:\s+(?:and|of|in|at|to|for)?\s*\1\b)+', caseSensitive: false), (m) => m[1]!);
  return t;
}

final _myNameIs = RegExp(r'\bmy name is ([A-Za-z]+)\b', caseSensitive: false);
final _shmiHu = RegExp(r'שמי (?:הוא|היא) ');

/// [translation] of English [source] into Hebrew, with the known fixes: Opus-MT
/// writes "My name is Idan" as "שמי הוא אידן" (a word-for-word "is", and the
/// name spelt from its sound). "שמי הוא" becomes "שמי", and a name from
/// [hebrewNames] gets its Hebrew spelling.
String applyHebrewGlossary(String source, String translation, {String gender = ''}) {
  var out = translation.replaceAll(_shmiHu, 'שמי ');
  if (gender == 'f') out = feminizeFirstPerson(out);
  if (gender == 'm') out = masculinizeFirstPerson(out);
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

/// Present-tense words that change for a woman speaking: masculine → feminine.
/// The models write the masculine ("אני עייף"); the past tense ("הלכתי") and
/// verbs like "רוצה" are the same for both and are not listed. Only words that
/// are only ever masculine after "אני" are here, so nothing is changed by guess.
const feminineForms = <String, String>{
  'עייף': 'עייפה', 'רעב': 'רעבה', 'צמא': 'צמאה', 'מוכן': 'מוכנה', 'בטוח': 'בטוחה', 'שמח': 'שמחה',
  'אבוד': 'אבודה', 'מבולבל': 'מבולבלת', 'עצבני': 'עצבנית', 'מבין': 'מבינה',
  'צריך': 'צריכה', 'יכול': 'יכולה', 'מעדיף': 'מעדיפה', 'מרגיש': 'מרגישה', 'מזמין': 'מזמינה',
  'חייב': 'חייבת', 'הולך': 'הולכת', 'יודע': 'יודעת', 'מחפש': 'מחפשת', 'מתכוון': 'מתכוונת',
  'אוהב': 'אוהבת', 'מדבר': 'מדברת', 'לומד': 'לומדת', 'נוסע': 'נוסעת', 'מתגעגע': 'מתגעגעת',
  'מצטער': 'מצטערת', 'עובד': 'עובדת', 'מתכנן': 'מתכננת', 'שומע': 'שומעת', 'מאחר': 'מאחרת',
  'גר': 'גרה', 'בא': 'באה', 'תייר': 'תיירת', 'תושב': 'תושבת', 'סטודנט': 'סטודנטית',
  'מתחיל': 'מתחילה', 'מסיים': 'מסיימת', 'משלם': 'משלמת', 'מתקשר': 'מתקשרת', 'שוכח': 'שוכחת',
  'זוכר': 'זוכרת', 'מקבל': 'מקבלת', 'נותן': 'נותנת', 'לוקח': 'לוקחת', 'חושב': 'חושבת', 'אומר': 'אומרת',
  'נהנה': 'נהנית', 'פוחד': 'פוחדת', 'מפחד': 'מפחדת',
  'מעוניין': 'מעוניינת', 'נשוי': 'נשואה', 'רווק': 'רווקה', 'מודאג': 'מודאגת', 'עסוק': 'עסוקה',
  'אלרגי': 'אלרגית', 'צמחוני': 'צמחונית', 'טבעוני': 'טבעונית',
};

final _iVerb = RegExp(
    r'(?<![א-ת])([ושכלמב]?אני)((?:\s+(?:לא|גם|כבר|ממש|מאוד|עכשיו|תמיד|פשוט|עדיין))?)\s+([א-ת]+)(?![א-ת])');

/// "אני עייף" → "אני עייפה": the speaker is a woman, so the words that follow
/// "אני" (one adverb allowed between) take the feminine form from [feminineForms].
String feminizeFirstPerson(String text) => text.replaceAllMapped(_iVerb, (m) {
      final f = feminineForms[m[3]];
      return f == null ? m[0]! : '${m[1]}${m[2]} $f';
    });

final _masculineForms = {for (final e in feminineForms.entries) if (e.key != e.value) e.value: e.key};

/// The other way: the model sometimes writes the feminine ("אני עייפה", "אני צמחונית")
/// for a man, so a speaker who said he is a man gets the masculine forms.
String masculinizeFirstPerson(String text) => text.replaceAllMapped(_iVerb, (m) {
      final f = _masculineForms[m[3]];
      return f == null ? m[0]! : '${m[1]}${m[2]} $f';
    });
