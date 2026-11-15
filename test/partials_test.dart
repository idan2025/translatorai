// Words appear while the sentence is still being spoken, grow, and are cleared when it is final.
//   TRANSLATORAI_MODELS=/models LD_LIBRARY_PATH=... flutter test test/partials_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';

void main() {
  final dir = Platform.environment['TRANSLATORAI_MODELS'];
  test('partial text grows while speaking and clears at the end', () async {
    so.initBindings();
    final w = await AsrWorker.start(AsrConfig(
        vad: '$dir/silero_vad.onnx',
        encoder: '$dir/base-encoder.int8.onnx',
        decoder: '$dir/base-decoder.int8.onnx',
        tokens: '$dir/base-tokens.txt',
        threads: 4,
        endSilence: 0.5));
    w.setPolicy(const LanguagePolicy(force: 'en'));
    w.setPartials(true);
    final events = <String>[];
    final finals = <Heard>[];
    final s1 = w.partialText.listen((t) => events.add(t));
    final s2 = w.heard.listen(finals.add);
    final wave = so.readWave('$dir/test1.wav'); // one long sentence, ~16 s
    final sw = Stopwatch()..start();
    for (var i = 0; i < wave.samples.length; i += 1600) {
      w.add(Float32List.sublistView(wave.samples, i, (i + 1600).clamp(0, wave.samples.length)));
      // roughly real time, so the worker has time to write partials between chunks
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 12; i++) {
      w.add(Float32List(1600));
    }
    await w.flushAndWait();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // ignore: avoid_print
    print('partials: ${events.where((e) => e.isNotEmpty).length}; first: "${events.firstWhere((e) => e.isNotEmpty, orElse: () => '')}"; last: "${events.lastWhere((e) => e.isNotEmpty, orElse: () => '')}"; cleared at end: ${events.isNotEmpty && events.last.isEmpty}; finals: ${finals.length} (${sw.elapsedMilliseconds} ms)');
    final shown = events.where((e) => e.isNotEmpty).toList();
    expect(shown.length, greaterThanOrEqualTo(2), reason: 'text appeared more than once while speaking');
    expect(shown.last.length, greaterThan(shown.first.length), reason: 'and it grew');
    expect(events.last, isEmpty, reason: 'cleared when the sentence was final');
    expect(finals, isNotEmpty);
    await s1.cancel();
    await s2.cancel();
    w.stop();
  }, skip: dir == null ? 'set TRANSLATORAI_MODELS' : false, timeout: const Timeout(Duration(minutes: 5)));
}
