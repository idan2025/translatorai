// End to end: clips through the voice detector, padding and recogniser, scored against
// the references, to choose the detector's sensitivity and pre-roll.
//   PW_AUDIO=dir PW_MODELS=dir PW_LANG=he PW_ENC=... flutter test test/pipeline_wer_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';

import 'bench_speech_test.dart' show edits, norm;

void main() {
  final dir = Platform.environment['PW_AUDIO'];
  final models = Platform.environment['PW_MODELS'];
  final lang = Platform.environment['PW_LANG'] ?? 'en';
  final enc = Platform.environment['PW_ENC'] ?? 'small-encoder.int8.onnx';
  final dec = Platform.environment['PW_DEC'] ?? 'small-decoder.int8.onnx';
  final tok = Platform.environment['PW_TOK'] ?? 'small-tokens.txt';
  final n = int.parse(Platform.environment['PW_N'] ?? '25');
  test('detector settings against final word errors', () {
    so.initBindings();
    final clips = File('$dir/trans.tsv').readAsLinesSync().where((l) => l.contains('\t')).map((l) => l.split('\t')).take(n).toList();
    for (final cfg in (Platform.environment['PW_CFGS'] ?? '0.5:0.3,0.3:0.8,0.2:0.8').split(',')) {
      final th = double.parse(cfg.split(':')[0]), pre = double.parse(cfg.split(':')[1]);
      final asr = Asr(AsrConfig(
          vad: '$models/silero_vad.onnx',
          encoder: '$models/$enc',
          decoder: '$models/$dec',
          tokens: '$models/$tok',
          threads: 4,
          endSilence: 0.4,
          vadThreshold: th,
          preRoll: pre))
        ..setPolicy(LanguagePolicy(force: lang));
      var we = 0, wn = 0, empty = 0;
      for (final c in clips) {
        final w = so.readWave('$dir/${c[0]}');
        final out = <Heard>[];
        for (var i = 0; i < w.samples.length; i += 1600) {
          out.addAll(asr.accept(Float32List.sublistView(w.samples, i, (i + 1600).clamp(0, w.samples.length))));
        }
        for (var q = 0; q < 12; q++) {
          out.addAll(asr.accept(Float32List(1600))); // 1.2 s of quiet, as after a real sentence
        }
        out.addAll(asr.flush());
        if (out.isEmpty) empty++;
        final hyp = norm(out.map((h) => h.text).join(' '));
        we += edits(hyp.split(' ').where((x) => x.isNotEmpty).toList(), norm(c[1]).split(' '));
        wn += norm(c[1]).split(' ').length;
      }
      asr.free();
      // ignore: avoid_print
      print('$lang threshold $th preroll ${pre}s: WER ${(100 * we / wn).toStringAsFixed(1)}%, clips with no text $empty/${clips.length}');
    }
  }, skip: dir == null || models == null ? 'set PW_AUDIO and PW_MODELS' : false, timeout: Timeout.none);
}
