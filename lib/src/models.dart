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
    'whisper-small',
    'Standard',
    'Whisper small · 99 languages · 375 MB · most phones',
    ModelFile('whisper-small-encoder.int8.onnx', '$_small/small-encoder.int8.onnx',
        '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9', 112442483),
    ModelFile('whisper-small-decoder.int8.onnx', '$_small/small-decoder.int8.onnx',
        'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee', 262226114),
    _tokens,
  ),
  SpeechModel(
    'whisper-turbo',
    'Best',
    'Whisper large-v3-turbo · 99 languages · 1 GB · recent phones with 6 GB+ RAM',
    ModelFile('whisper-turbo-encoder.int8.onnx', '$_turbo/turbo-encoder.int8.onnx',
        'b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b', 674716297),
    ModelFile('whisper-turbo-decoder.int8.onnx', '$_turbo/turbo-decoder.int8.onnx',
        '20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547', 361080764),
    _tokens,
  ),
];

SpeechModel speechModelById(String id) =>
    speechModels.firstWhere((m) => m.id == id, orElse: () => speechModels.first);
