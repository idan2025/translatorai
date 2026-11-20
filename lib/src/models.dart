/// The speech models the app downloads on first use. Each file is pinned by
/// URL *and* SHA-256: the digest decides, so a changed file at the same URL
/// is refused rather than run.
class ModelFile {
  const ModelFile(this.name, this.url, this.sha256, this.bytes);

  /// The file's name on the phone (unique across models).
  final String name;
  final String url;
  final String sha256;
  final int bytes;
}

/// A speech recogniser: Whisper, int8. Unlike Omnilingual (v0.2, replaced
/// after real-phone tests: on a phone microphone it mixed alphabets inside one
/// phrase and wrote Russian in Latin letters), Whisper can be told the language
/// to write in, so it can never come out in the wrong alphabet.
class SpeechModel {
  const SpeechModel(this.id, this.label, this.note, this.encoder, this.decoder, this.tokens);
  final String id;
  final String label;
  final String note;
  final ModelFile encoder, decoder, tokens;

  List<ModelFile> get files => [encoder, decoder, tokens];
  int get bytes => files.fold(0, (a, f) => a + f.bytes);
}

const _hf = 'https://huggingface.co/csukuangfj';
const _small = '$_hf/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309';
const _base = '$_hf/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc';
const _turbo = '$_hf/sherpa-onnx-whisper-turbo/resolve/2ca6ff69fc878651b770880507669577ac41c2ff';

const vadModel = ModelFile(
  'silero_vad.onnx',
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
  643854,
);

/// Both models share one vocabulary file (identical bytes).
const _tokens = ModelFile('whisper-tokens.txt', '$_small/small-tokens.txt',
    'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126', 816730);

const speechModels = <SpeechModel>[
  SpeechModel(
    'whisper-base',
    'Fast',
    'Whisper base · 99 languages · 160 MB · about 3x faster; rough on Hebrew and rare languages',
    ModelFile('whisper-base-encoder.int8.onnx', '$_base/base-encoder.int8.onnx',
        '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11', 29120534),
    ModelFile('whisper-base-decoder.int8.onnx', '$_base/base-decoder.int8.onnx',
        '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d', 130672026),
    _tokens,
  ),
  SpeechModel(
    'whisper-small',
    'Standard',
    'Whisper small · 99 languages · 375 MB · good balance',
    ModelFile('whisper-small-encoder.int8.onnx', '$_small/small-encoder.int8.onnx',
        '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9', 112442483),
    ModelFile('whisper-small-decoder.int8.onnx', '$_small/small-decoder.int8.onnx',
        'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee', 262226114),
    _tokens,
  ),
  SpeechModel(
    'whisper-turbo',
    'Best',
    'Whisper large-v3-turbo · 99 languages · 1 GB · most accurate, slow: for recent phones, short sentences',
    ModelFile('whisper-turbo-encoder.int8.onnx', '$_turbo/turbo-encoder.int8.onnx',
        'b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b', 674716297),
    ModelFile('whisper-turbo-decoder.int8.onnx', '$_turbo/turbo-decoder.int8.onnx',
        '20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547', 361080764),
    _tokens,
  ),
];

/// A speech model for one language, used only when that language is spoken
/// (next to the main model, which handles every other language). ivrit.ai's
/// Hebrew Whisper (Apache-2.0, a fine-tune of large-v3-turbo) cuts Hebrew word
/// errors from 38% to 28% on FLEURS, but it is Hebrew-only: English comes out 49%
/// wrong and Russian unreadable, so it cannot be the one model of a conversation.
class LanguagePack {
  const LanguagePack(this.id, this.label, this.note, this.language, this.encoder, this.decoder, this.tokens);
  final String id, label, note;
  final String language;
  final ModelFile encoder, decoder, tokens;
  List<ModelFile> get files => [encoder, decoder, tokens];
  int get bytes => files.fold(0, (a, f) => a + f.bytes);
}

const _hePack = 'https://huggingface.co/pantinor/whisper-large-v3-turbo-hebrew-sherpa/resolve/9dffea5951395ea70c3ced62cce35a94d9769338';

const hebrewPack = LanguagePack(
  'hebrew-turbo',
  'Hebrew speech pack',
  'ivrit.ai Hebrew Whisper (large-v3-turbo) · 1 GB · much better Hebrew; used only when Hebrew is spoken',
  'he',
  ModelFile('whisper-he-encoder.int8.onnx', '$_hePack/encoder.int8.onnx',
      '3e34e95500e7ea8479eda8b675ba920669c969a5ccc5531760d2d660fb332b17', 674622353),
  ModelFile('whisper-he-decoder.int8.onnx', '$_hePack/decoder.int8.onnx',
      '224878f5a3336970c01d272e1a8be6cb7bd4138421bcb5118d11bbdb17d84e2c', 361352573),
  _tokens,
);

const languagePacks = <LanguagePack>[hebrewPack];

/// One translation direction of a [TranslationPack]: an Opus-MT model run by
/// the app itself (`lib/src/marian.dart`), its files named `<tag>-<from>-<to>-…`
/// (`mt` for Opus-MT, `mq` for quickmt).
class TranslationDirection {
  const TranslationDirection(this.from, this.to, this.files, {this.tag = 'mt'});
  final String from, to;
  final List<ModelFile> files;
  final String tag;

  /// The file-name prefix the model's files share on the phone.
  String get prefix => '$tag-$from-$to-';
  int get bytes => files.fold(0, (a, f) => a + f.bytes);
}

/// Opus-MT translation models for one language and English, both ways: more
/// fluent than ML Kit's for that language. Other pairs with the language go
/// through English (ML Kit for the other side).
class TranslationPack {
  const TranslationPack(this.id, this.label, this.note, this.language, this.directions);
  final String id, label, note, language;
  final List<TranslationDirection> directions;
  List<ModelFile> get files => [for (final d in directions) ...d.files];
  int get bytes => files.fold(0, (a, f) => a + f.bytes);
}

/// Exported to ONNX and quantised to int8 from Helsinki-NLP's models (University
/// of Helsinki, Tiedemann et al.): opus-mt-tc-big-he-en (CC-BY 4.0) and
/// opus-mt-en-he (Apache-2.0). Hosted as assets of this project's release
/// `models-mt-1`. FLEURS chrF, 60 sentences, greedy, as the app runs it:
/// he→en 68.8, en→he 56.8.
const _mt = 'https://github.com/idan2025/translatorai/releases/download/models-mt-1';

ModelFile _mtFile(String d, String f, String sha, int bytes) => ModelFile('mt-$d-$f', '$_mt/mt-$d-$f', sha, bytes);

/// The first Hebrew translation pack (0.6.0–0.8.3). Kept working for phones that
/// have it until the quickmt pack replaces it (then its files are deleted).
final legacyOpusPack = TranslationPack(
  'hebrew-mt-opus',
  'Hebrew translation pack (older)',
  'Opus-MT Hebrew ⇄ English · 515 MB',
  'he',
  [
    TranslationDirection('he', 'en', [
      _mtFile('he-en', 'encoder.int8.onnx', 'ce843cbb8abbf79ed08a4918b69be5bf8de8046148ed8f5e1dbcee56bf76893d', 138724310),
      _mtFile('he-en', 'decoder.int8.onnx', '0df85ec1a6ac4d3079b6d35e29c9fbbf57869c302ee227362ebf7ac33d6d60bd', 226519278),
      _mtFile('he-en', 'source.spm', '13dabf370542066abcfd660e72887d0ce1296a04e15913d2ec47793656434257', 881489),
      _mtFile('he-en', 'vocab.json', 'abe93c914993f4dd8c10a7ff9cd97e813fcd1dd28dafb539504b509d8ad6183f', 2072892),
      _mtFile('he-en', 'config.json', 'ed3bfdb55358f54eaf7f13266c7742b47ed282a041c78ae1e610289dd6d41125', 1018),
    ]),
    TranslationDirection('en', 'he', [
      _mtFile('en-he', 'encoder.int8.onnx', 'cbfd33d39ab9588cd7055fe9f5e8c30f81f2292f6030f0d09eba69e9b9931213', 53150455),
      _mtFile('en-he', 'decoder.int8.onnx', '9042e911c7c7dcd189e32b336b09e9ed70582b2ed1ff20b7403475433f2ec57f', 94015921),
      _mtFile('en-he', 'source.spm', 'd390d1e87cfdc0f22eeb61aa787992cd4d622bbf8f5b9ae53eef3e9fda478967', 799290),
      _mtFile('en-he', 'vocab.json', '89133153ba25b6e818fa06c49682565ce8d62f17122c2b9a747691f174d3df3f', 2285475),
      _mtFile('en-he', 'config.json', '9ab6522942d36619903663fd7d4127e9a8f9d4eb6fca554f257e35da726da8bd', 1298),
    ]),
  ],
);

const _mq = 'https://github.com/idan2025/translatorai/releases/download/models-mt-2';

ModelFile _mqFile(String d, String f, String sha, int bytes) => ModelFile('mq-$d-$f', '$_mq/mq-$d-$f', sha, bytes);

/// quickmt (CC-BY 4.0), Hebrew ⇄ English: an 8-layer encoder and a 2-layer decoder
/// per direction, exported to ONNX and quantised to int8 (`lib/src/marian.dart`
/// runs its plain graph layout). Hosted as assets of this project's release
/// `models-mt-2`. FLEURS chrF, the same 60 sentences and greedy decoding as the
/// Opus-MT numbers above: he→en 68.7 (Opus 68.5), en→he 63.9 (Opus 57.6).
final hebrewTranslationPack = TranslationPack(
  'hebrew-mt',
  'Hebrew translation pack',
  'quickmt Hebrew ⇄ English · 546 MB · much more fluent Hebrew, fully offline',
  'he',
  [
    TranslationDirection('he', 'en', tag: 'mq', [
      _mqFile('he-en', 'encoder.int8.onnx', '7c38520ad06539f70605d42121dc101243ca88b92c5406811f3b7ec944e97822', 154184503),
      _mqFile('he-en', 'decoder.int8.onnx', 'f02bf4459dc41d1c393f26f952ebcc847738ba5d00858df446763284748d07ad', 119818091),
      _mqFile('he-en', 'source.spm', '006e2e0f144ae9425cf7ff6b81eb25de0165da5bfa8d220dfb75203ad9ca4ee4', 882724),
      _mqFile('he-en', 'vocab.json', '74035ad9552f3306e3192a862674993c597414c988e175bccf10652a8e3b4975', 632014),
      _mqFile('he-en', 'target-vocab.json', '076d60936ea7796502ce62aad73ae395a6d1e8d25daae436cab3270b557bb814', 551967),
      _mqFile('he-en', 'config.json', '8be22e1f4ea929f6d3441445541507ffe4c5de5cc3f8ed6881dc413d3938038d', 248),
    ]),
    TranslationDirection('en', 'he', tag: 'mq', [
      _mqFile('en-he', 'encoder.int8.onnx', '011a028e5d0f502354dd2b72743d8286c3b49c4b96d6996fccaf417c938c3911', 154184503),
      _mqFile('en-he', 'decoder.int8.onnx', 'd2220325fd3efce6ad251b26007f17b8404a9880c61b76eb21ce6893c7ed2b03', 119818091),
      _mqFile('en-he', 'source.spm', '38aadfae3dd591032d6e46ddcc38a7ec706e1f1429236ce9266882dba6c3ce83', 802664),
      _mqFile('en-he', 'vocab.json', '076d60936ea7796502ce62aad73ae395a6d1e8d25daae436cab3270b557bb814', 551967),
      _mqFile('en-he', 'target-vocab.json', '74035ad9552f3306e3192a862674993c597414c988e175bccf10652a8e3b4975', 632014),
      _mqFile('en-he', 'config.json', '106da1915d97b8bfd7f560520ef1157588803353cfecfb627f130a7682e6699e', 248),
    ]),
  ],
);

/// The packs the app offers. [legacyOpusPack] is not offered any more, only used
/// while it is on the phone and the new pack is not.
final translationPacks = <TranslationPack>[hebrewTranslationPack];

/// Every pack the translator may use, the newest first.
final usableTranslationPacks = <TranslationPack>[hebrewTranslationPack, legacyOpusPack];

/// The model used when nothing is chosen yet (or the chosen id is gone): Standard.
SpeechModel speechModelById(String id) =>
    speechModels.firstWhere((m) => m.id == id, orElse: () => speechModels.firstWhere((m) => m.id == 'whisper-small'));

/// Every file any speech model needs, plus the voice detector.
final List<ModelFile> allModelFiles = [
  vadModel,
  for (final m in speechModels) ...m.files,
  for (final k in languagePacks) ...k.files,
  for (final t in usableTranslationPacks) ...t.files,
];
