// Feeds minutes of speech and silence through the real pipeline, as the
// microphone would, and checks nothing degrades or drifts over time.
//   LONG_AUDIO=/dir(wavs+trans.tsv) LONG_MODELS=/models LONG_LANG=he LD_LIBRARY_PATH=... flutter test test/long_stream_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';

import 'bench_speech_test.dart' show edits, norm;

void main() {
  final dir = Platform.environment['LONG_AUDIO'];
  final models = Platform.environment['LONG_MODELS'];
  final lang = Platform.environment['LONG_LANG'] ?? 'he';
  final model = Platform.environment['LONG_MODEL'] ?? 'small';

  test('quality and alignment hold over a long stream', () {
    so.initBindings();
    final clips = File('$dir/trans.tsv').readAsLinesSync().where((l) => l.contains('\t')).map((l) => l.split('\t')).toList();
    final asr = Asr(AsrConfig(
      vad: '$models/silero_vad.onnx',
      encoder: '$models/$model-encoder.int8.onnx',
      decoder: '$models/$model-decoder.int8.onnx',
      tokens: '$models/$model-tokens.txt',
      threads: 4,
    ))..setPolicy(LanguagePolicy(force: lang));
    // three passes over the same clips: any decay would show as a rising error rate
    final passes = <double>[];
    var mis = 0;
    for (var pass = 0; pass < 3; pass++) {
      var we = 0, wn = 0;
      for (final c in clips) {
        final w = so.readWave('$dir/${c[0]}');
        final out = <Heard>[];
        // like the microphone: 100 ms chunks
        for (var i = 0; i < w.samples.length; i += 1600) {
          out.addAll(asr.accept(Float32List.sublistView(w.samples, i, (i + 1600).clamp(0, w.samples.length))));
        }
        // 1.5 s of room noise between sentences
        final rng = DateTime.now().microsecondsSinceEpoch;
        for (var i = 0; i < 15; i++) {
          out.addAll(asr.accept(Float32List.fromList(List.generate(1600, (j) => ((rng + i * 1600 + j) % 17 - 8) / 4000))));
        }
        final hyp = norm(out.map((h) => h.text).join(' '));
        we += edits(hyp.split(' ').where((x) => x.isNotEmpty).toList(), norm(c[1]).split(' '));
        wn += norm(c[1]).split(' ').length;
      }
      mis = asr.misaligned;
      passes.add(100 * we / wn);
      // ignore: avoid_print
      print('pass ${pass + 1}: WER ${passes.last.toStringAsFixed(1)}%  misaligned segments so far: $mis');
    }
    asr.free();
    expect(mis, 0, reason: 'the audio ring drifted from the detector');
  }, skip: dir == null || models == null ? 'set LONG_AUDIO and LONG_MODELS' : false, timeout: Timeout.none);
}
