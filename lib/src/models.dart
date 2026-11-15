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

/// The model used when nothing is chosen yet (or the chosen id is gone): Standard.
SpeechModel speechModelById(String id) =>
    speechModels.firstWhere((m) => m.id == id, orElse: () => speechModels.firstWhere((m) => m.id == 'whisper-small'));

/// Every file any speech model needs, plus the voice detector.
final List<ModelFile> allModelFiles = [
  vadModel,
  for (final m in speechModels) ...m.files,
  for (final k in languagePacks) ...k.files,
];
