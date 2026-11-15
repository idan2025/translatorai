// Speech model benchmark on real recordings: error rate, language detection
// and speed. Not part of the normal test run (skipped unless BENCH_AUDIO is set).
//
//   BENCH_AUDIO=/dir/with/wavs+trans.tsv  BENCH_MODELS=/models  BENCH_LANG=he \
//   LD_LIBRARY_PATH=~/.pub-cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64 \
//   flutter test test/bench_speech_test.dart
//
// trans.tsv: "<file.wav>\t<reference text>" per line, audio 16 kHz mono PCM16.
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';
import 'package:translatorai/src/languages.dart';

/// Lowercase, no punctuation or Hebrew/Arabic diacritics, single spaces.
String norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[֑-ׇً-ٟ]'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int edits<T>(List<T> a, List<T> b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[b.length];
}

class Candidate {
  Candidate(this.name, this.config);
  final String name;
  final so.OfflineModelConfig config;
}

void main() {
  final audio = Platform.environment['BENCH_AUDIO'];
  final models = Platform.environment['BENCH_MODELS'];
  final lang = Platform.environment['BENCH_LANG'] ?? 'he';
  final only = Platform.environment['BENCH_ONLY'];
  final threads = int.parse(Platform.environment['BENCH_THREADS'] ?? '4');
  // seconds of silence appended to every clip (the engine drops the last words of a clip that ends abruptly)
  final padSec = double.parse(Platform.environment['BENCH_PAD'] ?? '0');

  test('speech models on real $lang recordings', () {
    so.initBindings();
    final clips = File('$audio/trans.tsv')
        .readAsLinesSync()
        .where((l) => l.contains('\t'))
        .map((l) => l.split('\t'))
        .toList();

    so.OfflineModelConfig whisper(String size, String language) => so.OfflineModelConfig(
          whisper: so.OfflineWhisperModelConfig(
            encoder: '$models/$size-encoder.int8.onnx',
            decoder: '$models/$size-decoder.int8.onnx',
            language: language,
            task: 'transcribe',
          ),
          tokens: '$models/$size-tokens.txt',
          numThreads: threads,
          debug: false,
        );
    so.OfflineModelConfig omni(String dir) => so.OfflineModelConfig(
          omnilingual: so.OfflineOmnilingualAsrCtcModelConfig(model: '$models/$dir/model.int8.onnx'),
          tokens: '$models/$dir/tokens.txt',
          numThreads: threads,
          debug: false,
        );

    final cands = <Candidate>[
      for (final size in ['tiny', 'base', 'small', 'turbo', 'medium'])
        if (File('$models/$size-encoder.int8.onnx').existsSync()) ...[
          Candidate('whisper-$size auto', whisper(size, '')),
          Candidate('whisper-$size $lang', whisper(size, lang)),
        ],
      for (final dir in ['omni300', 'omni1b'])
        if (File('$models/$dir/model.int8.onnx').existsSync()) Candidate(dir, omni(dir)),
      for (final dir in ['ivrit-turbo'])
        if (File('$models/$dir/turbo-encoder.int8.onnx').existsSync())
          Candidate('$dir $lang', so.OfflineModelConfig(
            whisper: so.OfflineWhisperModelConfig(
              encoder: '$models/$dir/turbo-encoder.int8.onnx',
              decoder: '$models/$dir/turbo-decoder.int8.onnx',
              language: lang,
              task: 'transcribe',
            ),
            tokens: '$models/$dir/turbo-tokens.txt',
            numThreads: threads,
            debug: false,
          )),
    ].where((c) => only == null || c.name.contains(only)).toList();

    for (final c in cands) {
      final rec = so.OfflineRecognizer(so.OfflineRecognizerConfig(model: c.config));
      var we = 0, wn = 0, ce = 0, cn = 0, rightLang = 0, langs = 0;
      var audioSec = 0.0;
      final sw = Stopwatch();
      final samples = <String>[];
      for (final clip in clips) {
        final wave = so.readWave('$audio/${clip[0]}');
        audioSec += wave.samples.length / wave.sampleRate;
        final s = rec.createStream();
        sw.start();
        final padded = Float32List(wave.samples.length + (padSec * wave.sampleRate).round())..setRange(0, wave.samples.length, wave.samples);
        s.acceptWaveform(samples: padded, sampleRate: wave.sampleRate);
        rec.decode(s);
        final r = rec.getResult(s);
        sw.stop();
        s.free();
        final hyp = norm(cleanText(r.text)), ref = norm(clip[1]);
        we += edits(hyp.split(' ').where((w) => w.isNotEmpty).toList(), ref.split(' '));
        wn += ref.split(' ').length;
        ce += edits(hyp.replaceAll(' ', '').split(''), ref.replaceAll(' ', '').split(''));
        cn += ref.replaceAll(' ', '').length;
        final l = normaliseLanguageTag(r.lang);
        if (l.isNotEmpty) {
          langs++;
          if (l == lang) rightLang++;
        }
        if (samples.length < 2) samples.add('    ref: ${clip[1]}\n    hyp: ${r.text.trim()}  [$l]');
      }
      rec.free();
      // ignore: avoid_print
      print('${c.name.padRight(22)} WER ${(100 * we / wn).toStringAsFixed(1).padLeft(5)}%  '
          'CER ${(100 * ce / cn).toStringAsFixed(1).padLeft(5)}%  '
          'lang ${langs == 0 ? '  n/a' : '$rightLang/$langs'.padLeft(5)}  '
          'RTF ${(sw.elapsedMilliseconds / 1000 / audioSec).toStringAsFixed(3)}  '
          '(${(sw.elapsedMilliseconds / clips.length).round()} ms/clip, $threads threads)\n${samples.join('\n')}');
    }
  }, skip: audio == null || models == null ? 'set BENCH_AUDIO and BENCH_MODELS' : false, timeout: Timeout.none);
}
