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

/// A speech recogniser. Omnilingual (Meta, Apache 2.0) writes what it hears
/// in that language's own alphabet without guessing a language first, so it
/// never "hears" Russian as Polish; the language is told from the text after.
class SpeechModel {
  const SpeechModel(this.id, this.label, this.note, this.model, this.tokens);
  final String id;
  final String label;
  final String note;
  final ModelFile model;
  final ModelFile tokens;

  List<ModelFile> get files => [model, tokens];
  int get bytes => model.bytes + tokens.bytes;
}

const _hf = 'https://huggingface.co/csukuangfj';
const _omni300 = '$_hf/sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-int8-2025-11-12/resolve/6abf1ece20cd2308bdb7d13cd78ec1c44fa4c094';
const _omni1b = '$_hf/sherpa-onnx-omnilingual-asr-1600-languages-1B-ctc-int8-2025-11-12/resolve/17db76eab583b0b868ffb0df104ab879145087e5';

const vadModel = ModelFile(
  'silero_vad.onnx',
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
  643854,
);

/// Both models share one vocabulary file (identical bytes).
const _omniTokens = ModelFile('omni-tokens.txt', '$_omni300/tokens.txt',
    'a7a044c52cb29cbe8b0dc1953e92cefd4ca16b0ed968177b6beab21f9a7d0b31', 86423);

const speechModels = <SpeechModel>[
  SpeechModel(
    'omni-300m',
    'Standard',
    'Omnilingual 300M · 1,600 languages · 365 MB · most phones',
    ModelFile('omni-300m.int8.onnx', '$_omni300/model.int8.onnx',
        'e7c4e54ee4c4c47829cc6667d5d00ed8ea7bef1dcfeef0fce766f77752a2726c', 365352120),
    _omniTokens,
  ),
  SpeechModel(
    'omni-1b',
    'Best',
    'Omnilingual 1B · 1,600 languages · 1 GB · recent phones with 6 GB+ RAM',
    ModelFile('omni-1b.int8.onnx', '$_omni1b/model.int8.onnx',
        'f7b74c964039162423b83e3fa950ce24810c9a635d9ff8468b5f4d142b7c1e8c', 1031628252),
    _omniTokens,
  ),
];

SpeechModel speechModelById(String id) =>
    speechModels.firstWhere((m) => m.id == id, orElse: () => speechModels.first);
