/// Every language the app knows, and which stage can handle it.
///
/// A language is usable as a *source* when the speech model (Whisper, 99
/// languages) hears it, and as a *target* when the translation engine writes
/// it. Any pair of those works: there is no fixed list of pairs.
class Language {
  const Language(this.code, this.name);

  /// ISO 639-1 where one exists (what Whisper and ML Kit both use).
  final String code;
  final String name;

  @override
  bool operator ==(Object other) => other is Language && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$name ($code)';
}

/// The languages Whisper hears (its multilingual vocabulary, 99 entries).
const knownLanguages = <Language>[
  Language('en', 'English'), Language('zh', 'Chinese'), Language('de', 'German'),
  Language('es', 'Spanish'), Language('ru', 'Russian'), Language('ko', 'Korean'),
  Language('fr', 'French'), Language('ja', 'Japanese'), Language('pt', 'Portuguese'),
  Language('tr', 'Turkish'), Language('pl', 'Polish'), Language('ca', 'Catalan'),
  Language('nl', 'Dutch'), Language('ar', 'Arabic'), Language('sv', 'Swedish'),
  Language('it', 'Italian'), Language('id', 'Indonesian'), Language('hi', 'Hindi'),
  Language('fi', 'Finnish'), Language('vi', 'Vietnamese'), Language('he', 'Hebrew'),
  Language('uk', 'Ukrainian'), Language('el', 'Greek'), Language('ms', 'Malay'),
  Language('cs', 'Czech'), Language('ro', 'Romanian'), Language('da', 'Danish'),
  Language('hu', 'Hungarian'), Language('ta', 'Tamil'), Language('no', 'Norwegian'),
  Language('th', 'Thai'), Language('ur', 'Urdu'), Language('hr', 'Croatian'),
  Language('bg', 'Bulgarian'), Language('lt', 'Lithuanian'), Language('la', 'Latin'),
  Language('mi', 'Maori'), Language('ml', 'Malayalam'), Language('cy', 'Welsh'),
  Language('sk', 'Slovak'), Language('te', 'Telugu'), Language('fa', 'Persian'),
  Language('lv', 'Latvian'), Language('bn', 'Bengali'), Language('sr', 'Serbian'),
  Language('az', 'Azerbaijani'), Language('sl', 'Slovenian'), Language('kn', 'Kannada'),
  Language('et', 'Estonian'), Language('mk', 'Macedonian'), Language('br', 'Breton'),
  Language('eu', 'Basque'), Language('is', 'Icelandic'), Language('hy', 'Armenian'),
  Language('ne', 'Nepali'), Language('mn', 'Mongolian'), Language('bs', 'Bosnian'),
  Language('kk', 'Kazakh'), Language('sq', 'Albanian'), Language('sw', 'Swahili'),
  Language('gl', 'Galician'), Language('mr', 'Marathi'), Language('pa', 'Punjabi'),
  Language('si', 'Sinhala'), Language('km', 'Khmer'), Language('sn', 'Shona'),
  Language('yo', 'Yoruba'), Language('so', 'Somali'), Language('af', 'Afrikaans'),
  Language('oc', 'Occitan'), Language('ka', 'Georgian'), Language('be', 'Belarusian'),
  Language('tg', 'Tajik'), Language('sd', 'Sindhi'), Language('gu', 'Gujarati'),
  Language('am', 'Amharic'), Language('yi', 'Yiddish'), Language('lo', 'Lao'),
  Language('uz', 'Uzbek'), Language('fo', 'Faroese'), Language('ht', 'Haitian Creole'),
  Language('ps', 'Pashto'), Language('tk', 'Turkmen'), Language('nn', 'Nynorsk'),
  Language('mt', 'Maltese'), Language('sa', 'Sanskrit'), Language('lb', 'Luxembourgish'),
  Language('my', 'Myanmar'), Language('bo', 'Tibetan'), Language('tl', 'Tagalog'),
  Language('mg', 'Malagasy'), Language('as', 'Assamese'), Language('tt', 'Tatar'),
  Language('haw', 'Hawaiian'), Language('ln', 'Lingala'), Language('ha', 'Hausa'),
  Language('ba', 'Bashkir'), Language('jw', 'Javanese'), Language('su', 'Sundanese'),
];

/// Languages a translation engine writes that Whisper cannot hear: targets only.
const moreLanguages = <Language>[Language('eo', 'Esperanto'), Language('ga', 'Irish')];

/// Codes the speech model can hear.
final Set<String> hearable = {for (final l in knownLanguages) l.code};

/// A recogniser's language tag ("en", "<|en|>", " en") as a plain code.
String normaliseLanguageTag(String raw) {
  final t = raw.trim().replaceAll('<|', '').replaceAll('|>', '').toLowerCase();
  return t;
}

Language? languageByCode(String code) {
  for (final l in [...knownLanguages, ...moreLanguages]) {
    if (l.code == code) return l;
  }
  return null;
}

String nameOf(String code) => languageByCode(code)?.name ?? code;

/// Every known language, sorted by name.
List<Language> allLanguages() =>
    [...knownLanguages, ...moreLanguages]..sort((a, b) => a.name.compareTo(b.name));
