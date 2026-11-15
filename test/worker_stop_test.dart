// The last sentence must survive a stop: speak, stop at once, and the text
// still arrives. Runs the real background worker and models.
//   TRANSLATORAI_MODELS=/models LD_LIBRARY_PATH=... flutter test test/worker_stop_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';

void main() {
  final dir = Platform.environment['TRANSLATORAI_MODELS'];
  test('a sentence still being written when you stop is not lost', () async {
    so.initBindings();
    final w = await AsrWorker.start(AsrConfig(
        vad: '$dir/silero_vad.onnx',
        encoder: '$dir/small-encoder.int8.onnx',
        decoder: '$dir/small-decoder.int8.onnx',
        tokens: '$dir/small-tokens.txt',
        threads: 4));
    final heard = <Heard>[];
    final phases = <String>[];
    final sub = w.heard.listen(heard.add);
    final psub = w.phases.listen(phases.add);
    w.setPolicy(const LanguagePolicy(force: 'en'));
    w.setEndSilence(0.4);
    final wave = so.readWave('$dir/test0.wav');
    for (var i = 0; i < wave.samples.length; i += 1600) {
      w.add(Float32List.sublistView(wave.samples, i, (i + 1600).clamp(0, wave.samples.length)));
    }
    // stop right after the last word: no trailing quiet at all
    final sw = Stopwatch()..start();
    await w.flushAndWait();
    // ignore: avoid_print
    print('flush answered after ${sw.elapsedMilliseconds} ms; heard: ${heard.map((h) => h.text)}; phases: $phases');
    expect(heard.map((h) => h.text).join(' ').toLowerCase(), contains('nightfall'));
    // the same loaded worker serves the next start
    heard.clear();
    for (var i = 0; i < wave.samples.length; i += 1600) {
      w.add(Float32List.sublistView(wave.samples, i, (i + 1600).clamp(0, wave.samples.length)));
    }
    await w.flushAndWait();
    expect(heard, isNotEmpty);
    await sub.cancel();
    await psub.cancel();
    w.stop();
  }, skip: dir == null ? 'set TRANSLATORAI_MODELS' : false, timeout: const Timeout(Duration(minutes: 5)));
}
