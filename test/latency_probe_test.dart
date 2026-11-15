// How decode time depends on clip length and threads. Skipped unless PROBE_DIR is set.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

void main() {
  final dir = Platform.environment['PROBE_DIR'];
  final models = Platform.environment['PROBE_MODELS'];
  test('decode time vs clip length', () {
    so.initBindings();
    for (final size in (Platform.environment['PROBE_SIZES'] ?? 'small,turbo').split(',')) {
      for (final threads in [2, 4, 8]) {
        final rec = so.OfflineRecognizer(so.OfflineRecognizerConfig(
          model: so.OfflineModelConfig(
            whisper: so.OfflineWhisperModelConfig(
                encoder: '$models/$size-encoder.int8.onnx', decoder: '$models/$size-decoder.int8.onnx', language: 'en', task: 'transcribe'),
            tokens: '$models/$size-tokens.txt',
            numThreads: threads,
            debug: false,
          ),
        ));
        final row = StringBuffer('$size t=$threads:');
        for (final d in ['1.4', '4', '8', '14']) {
          final w = so.readWave('$dir/c$d.wav');
          // first call includes warm-up: time the second
          for (var k = 0; k < 2; k++) {
            final s = rec.createStream();
            s.acceptWaveform(samples: w.samples, sampleRate: w.sampleRate);
            final sw = Stopwatch()..start();
            rec.decode(s);
            if (k == 1) row.write('  ${d}s→${sw.elapsedMilliseconds}ms');
            s.free();
          }
        }
        rec.free();
        // ignore: avoid_print
        print(row);
      }
    }
  }, skip: dir == null ? 'set PROBE_DIR' : false, timeout: Timeout.none);
}
