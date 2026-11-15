import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

void main() {
  final dirs = Platform.environment['VAD_DIRS']; // comma separated
  final models = Platform.environment['VAD_MODELS'];
  test('how much speech the detector finds', () {
    so.initBindings();
    for (final dir in dirs!.split(',')) {
      final clips = File('$dir/trans.tsv').readAsLinesSync().where((l) => l.contains('\t')).map((l) => l.split('\t')).take(40).toList();
      for (final th in [0.5, 0.4, 0.3, 0.2]) {
        var none = 0, coveredSum = 0.0, total = 0.0, firstLate = 0.0, fragments = 0;
        for (final c in clips) {
          final vad = so.VoiceActivityDetector(
              config: so.VadModelConfig(
                  sileroVad: so.SileroVadModelConfig(
                      model: '$models/silero_vad.onnx', threshold: th, minSilenceDuration: 0.4, minSpeechDuration: 0.25, maxSpeechDuration: 10),
                  sampleRate: 16000, numThreads: 1, debug: false),
              bufferSizeInSeconds: 60);
          final w = so.readWave('$dir/${c[0]}');
          // the clip's own speech span: first and last sample above a loose energy floor
          int first = -1, last = -1;
          for (var i = 0; i < w.samples.length; i += 160) {
            double e = 0;
            for (var j = i; j < i + 160 && j < w.samples.length; j++) { e += w.samples[j] * w.samples[j]; }
            if (e / 160 > 1e-5) { if (first < 0) first = i; last = i; }
          }
          final segs = <(int, int)>[];
          void drain() {
            while (!vad.isEmpty()) {
              final s = vad.front();
              vad.pop();
              segs.add((s.start, s.start + s.samples.length));
            }
          }
          for (var i = 0; i < w.samples.length; i += 1600) {
            vad.acceptWaveform(Float32List.sublistView(w.samples, i, (i + 1600).clamp(0, w.samples.length)));
            drain();
          }
          vad.flush();
          drain();
          vad.free();
          final span = (last - first).clamp(1, 1 << 30);
          var cov = 0;
          for (final s in segs) { cov += (s.$2.clamp(first, last) - s.$1.clamp(first, last)).clamp(0, 1 << 30); }
          if (segs.isEmpty) none++;
          coveredSum += cov / span;
          total += 1;
          fragments += segs.length;
          if (segs.isNotEmpty) firstLate += (segs.first.$1 - first) / 16000;
        }
        // ignore: avoid_print
        print('$dir  threshold $th: clips with NO speech found $none/${clips.length}, speech covered ${(100 * coveredSum / total).toStringAsFixed(0)}%, pieces per clip ${(fragments / total).toStringAsFixed(1)}, first piece starts ${(firstLate / (total - none)).toStringAsFixed(2)} s late');
      }
    }
  }, skip: dirs == null ? 'set VAD_DIRS' : false, timeout: const Timeout(Duration(minutes: 10)));
}
