// Compares ways of turning mixed-language speech into text with the right
// language, on real recordings (FLEURS) clean and with phone-like noise.
// Not part of the normal run (skipped unless BENCH_SETS is set).
//
//   BENCH_SETS="he:/dir1,ru:/dir2,en:/dir3"  BENCH_MODELS=/models  BENCH_MODEL=small \
//   LD_LIBRARY_PATH=.../sherpa_onnx_linux-2.0.1/linux/x64 flutter test test/bench_strategy_test.dart
//
// Each dir holds 16 kHz mono PCM16 wavs and trans.tsv ("file\treference").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:translatorai/src/asr.dart';
import 'package:translatorai/src/languages.dart';
import 'package:translatorai/src/lid.dart';

import 'bench_speech_test.dart' show edits, norm;

class Clip {
  Clip(this.lang, this.samples, this.ref);
  final String lang, ref;
  final List<double> samples;
}

void main() {
  final sets = Platform.environment['BENCH_SETS'];
  final models = Platform.environment['BENCH_MODELS'];
  final size = Platform.environment['BENCH_MODEL'] ?? 'small';
  final threads = int.parse(Platform.environment['BENCH_THREADS'] ?? '4');

  test('language strategies on mixed speech', () {
    so.initBindings();
    final clips = <Clip>[];
    final wavs = <so.WaveData>[];
    for (final part in sets!.split(',')) {
      final lang = part.split(':').first, dir = part.substring(lang.length + 1);
      for (final l in File('$dir/trans.tsv').readAsLinesSync().where((l) => l.contains('\t'))) {
        final f = l.split('\t');
        wavs.add(so.readWave('$dir/${f[0]}'));
        clips.add(Clip(lang, const [], f[1]));
      }
    }

    so.OfflineRecognizerConfig cfg(String lang) => so.OfflineRecognizerConfig(
          model: so.OfflineModelConfig(
            whisper: so.OfflineWhisperModelConfig(
              encoder: '$models/$size-encoder.int8.onnx',
              decoder: '$models/$size-decoder.int8.onnx',
              language: lang,
              task: 'transcribe',
            ),
            tokens: '$models/$size-tokens.txt',
            numThreads: threads,
            debug: false,
          ),
        );

    final rec = so.OfflineRecognizer(cfg(''));
    var current = '';
    ({String text, String lang}) decode(so.WaveData w, String lang) {
      if (lang != current) {
        rec.setConfig(cfg(lang));
        current = lang;
      }
      final s = rec.createStream();
      s.acceptWaveform(samples: w.samples, sampleRate: w.sampleRate);
      rec.decode(s);
      final r = rec.getResult(s);
      s.free();
      return (text: cleanText(r.text), lang: normaliseLanguageTag(r.lang));
    }

    // proof that switching the language on one recogniser really changes the output
    final probe = decode(wavs.first, 'en');
    final probe2 = decode(wavs.first, clips.first.lang);
    // ignore: avoid_print
    print('setConfig check (${clips.first.lang} audio): forced en → "${probe.text}"  forced ${clips.first.lang} → "${probe2.text}"');

    final pairs = [
      ['he', 'en'],
      ['ru', 'en'],
      ['he', 'ru'],
    ];
    final strategies = <String, ({String lang, String text}) Function(so.WaveData, Set<String>)>{
      // what v0.1 did: the recogniser's own guess, whatever it is
      'auto (v0.1)': (w, pair) => decode(w, ''),
      // auto, but a guess outside the pair is replaced by forcing each side and taking the one whose text fits its alphabet
      'auto, kept inside the pair': (w, pair) {
        final a = decode(w, '');
        if (pair.contains(a.lang)) return a;
        String? best;
        var bestText = '';
        for (final l in pair) {
          final d = decode(w, l);
          if (bestText.isEmpty || (writtenIn(l, scriptOf(d.text)) && d.text.length > bestText.length)) {
            best = l;
            bestText = d.text;
          }
        }
        return (lang: best ?? pair.first, text: bestText);
      },
    };

    for (final pair in pairs) {
      final idx = [for (var i = 0; i < clips.length; i++) if (pair.contains(clips[i].lang)) i];
      for (final e in strategies.entries) {
        var ok = 0, we = 0, wn = 0;
        final sw = Stopwatch()..start();
        for (final i in idx) {
          final r = e.value(wavs[i], pair.toSet());
          if (r.lang == clips[i].lang) ok++;
          final ref = norm(clips[i].ref), hyp = norm(r.text);
          we += edits(hyp.split(' ').where((w) => w.isNotEmpty).toList(), ref.split(' '));
          wn += ref.split(' ').length;
        }
        sw.stop();
        // ignore: avoid_print
        print('${pair.join('+')}  ${e.key.padRight(28)} language right $ok/${idx.length}  '
            'WER ${(100 * we / wn).toStringAsFixed(1)}%  ${(sw.elapsedMilliseconds / idx.length).round()} ms/clip');
      }
      // the baseline that cannot be beaten: told the language up front
      var we = 0, wn = 0;
      final sw = Stopwatch()..start();
      for (final i in idx) {
        final r = decode(wavs[i], clips[i].lang);
        we += edits(norm(r.text).split(' ').where((w) => w.isNotEmpty).toList(), norm(clips[i].ref).split(' '));
        wn += norm(clips[i].ref).split(' ').length;
      }
      // ignore: avoid_print
      print('${pair.join('+')}  ${'language known (ceiling)'.padRight(28)} language right ${idx.length}/${idx.length}  '
          'WER ${(100 * we / wn).toStringAsFixed(1)}%  ${(sw.elapsedMilliseconds / idx.length).round()} ms/clip');
    }
    rec.free();
  }, skip: sets == null || models == null ? 'set BENCH_SETS and BENCH_MODELS' : false, timeout: Timeout.none);
}
