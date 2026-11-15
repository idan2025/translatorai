/// The speech models the app downloads on first use. Each file is pinned by
/// URL *and* SHA-256: the digest decides, so a changed file at the same URL
/// is refused rather than run.
class ModelFile {
  const ModelFile(this.name, this.url, this.sha256, this.bytes);
  final String name;
  final String url;
  final String sha256;
  final int bytes;
}

class SpeechModel {
  const SpeechModel(this.id, this.label, this.note, this.files);
  final String id;
  final String label;
  final String note;
  final List<ModelFile> files;

  int get bytes => files.fold(0, (a, f) => a + f.bytes);
  String get encoder => files.firstWhere((f) => f.name.endsWith('encoder.int8.onnx')).name;
  String get decoder => files.firstWhere((f) => f.name.endsWith('decoder.int8.onnx')).name;
  String get tokens => files.firstWhere((f) => f.name.endsWith('tokens.txt')).name;
}

const _hf = 'https://huggingface.co/csukuangfj';
const _tiny = '65176e2deb88badc814a94058666cadccc29b61c';
const _base = 'bb53ee204431c90d314c1cc08d28d23e5b7927cc';

const vadModel = ModelFile(
  'silero_vad.onnx',
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
  643854,
);

const speechModels = <SpeechModel>[
  SpeechModel('whisper-tiny', 'Fast', 'Whisper tiny · 99 languages · ~100 MB · any phone', [
    ModelFile('tiny-encoder.int8.onnx', '$_hf/sherpa-onnx-whisper-tiny/resolve/$_tiny/tiny-encoder.int8.onnx',
        'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434', 12937772),
    ModelFile('tiny-decoder.int8.onnx', '$_hf/sherpa-onnx-whisper-tiny/resolve/$_tiny/tiny-decoder.int8.onnx',
        'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925', 89855401),
    ModelFile('tiny-tokens.txt', '$_hf/sherpa-onnx-whisper-tiny/resolve/$_tiny/tiny-tokens.txt',
        'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126', 816730),
  ]),
  SpeechModel('whisper-base', 'Accurate', 'Whisper base · 99 languages · ~160 MB · newer phones', [
    ModelFile('base-encoder.int8.onnx', '$_hf/sherpa-onnx-whisper-base/resolve/$_base/base-encoder.int8.onnx',
        '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11', 29120534),
    ModelFile('base-decoder.int8.onnx', '$_hf/sherpa-onnx-whisper-base/resolve/$_base/base-decoder.int8.onnx',
        '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d', 130672026),
    ModelFile('base-tokens.txt', '$_hf/sherpa-onnx-whisper-base/resolve/$_base/base-tokens.txt',
        'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126', 816730),
  ]),
];

SpeechModel speechModelById(String id) =>
    speechModels.firstWhere((m) => m.id == id, orElse: () => speechModels.first);
