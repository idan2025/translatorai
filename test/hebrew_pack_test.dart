// The Hebrew pack through the real background worker and voice detector, on a
// real Hebrew recording. Skipped unless HEBREW_MODELS and HEBREW_AUDIO are set.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';

void main() {
  final models = Platform.environment['HEBREW_MODELS'];
  final audio = Platform.environment['HEBREW_AUDIO'];
  test('the Hebrew pack writes Hebrew through the worker', () async {
    so.initBindings();
    final rows = File('$audio/trans.tsv').readAsLinesSync().where((l) => l.contains('\t')).map((l) => l.split('\t')).take(3).toList();
    final w = await AsrWorker.start(AsrConfig(
        vad: '$models/silero_vad.onnx',
        encoder: '$models/ivrit-turbo/encoder.int8.onnx',
        decoder: '$models/ivrit-turbo/decoder.int8.onnx',
        tokens: '$models/ivrit-turbo/tokens.txt',
        threads: 4,
        endSilence: 0.4));
    w.setPolicy(const LanguagePolicy(force: 'he'));
    final heard = <Heard>[];
    final sub = w.heard.listen(heard.add);
    for (final r in rows) {
      final wave = so.readWave('$audio/${r[0]}');
      for (var i = 0; i < wave.samples.length; i += 1600) {
        w.add(Float32List.sublistView(wave.samples, i, (i + 1600).clamp(0, wave.samples.length)));
      }
      await w.flushAndWait();
    }
    // ignore: avoid_print
    for (final h in heard) { print('he pack: [${h.language}${h.forced ? ' forced' : ''}] ${h.text}'); }
    expect(heard, isNotEmpty);
    expect(heard.every((h) => h.language == 'he' && h.forced), isTrue);
    expect(heard.first.text, contains('עוצמתה'));
    await sub.cancel();
    w.stop();
  }, skip: models == null || audio == null ? 'set HEBREW_MODELS and HEBREW_AUDIO' : false, timeout: const Timeout(Duration(minutes: 5)));
}
