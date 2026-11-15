// Runs the real speech models on this machine. Needs the model files:
//   TRANSLATORAI_MODELS=/path/with/silero_vad.onnx,tiny-*.onnx,test0.wav flutter test test/asr_models_test.dart
// Skipped when the variable is unset, so `flutter test` stays offline.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';

void main() {
  final dir = Platform.environment['TRANSLATORAI_MODELS'];
  for (final size in ['small']) {
    test('$size hears English speech through the detector, with margins and a forced language', () {
      so.initBindings();
      final asr = Asr(AsrConfig(
        vad: '$dir/silero_vad.onnx',
        encoder: '$dir/$size-encoder.int8.onnx',
        decoder: '$dir/$size-decoder.int8.onnx',
        tokens: '$dir/$size-tokens.txt',
        threads: 2,
      ));
      final wave = so.readWave('$dir/test0.wav');
      asr.setPolicy(const LanguagePolicy(allowed: {'en', 'ru'}));
      expect(wave.sampleRate, sampleRate);
      // feed it the way the microphone does: 100 ms chunks, then silence
      final heard = <Heard>[];
      final s = wave.samples;
      for (var i = 0; i < s.length; i += 1600) {
        heard.addAll(asr.accept(Float32List.sublistView(s, i, (i + 1600).clamp(0, s.length))));
      }
      heard.addAll(asr.accept(Float32List(sampleRate)));
      heard.addAll(asr.flush());
      asr.free();
      // ignore: avoid_print
      for (final h in heard) { print('$size: $h'); }
      final text = heard.map((h) => h.text).join(' ').toLowerCase();
      expect(text, contains('nightfall'));
      expect(text, contains('lamps'));
      expect(heard.first.language, 'en');
    }, skip: dir == null ? 'set TRANSLATORAI_MODELS to run' : false);
  }
}
