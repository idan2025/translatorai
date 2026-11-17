// Opus-MT through the app's own ONNX Runtime binding and tokenizer, against
// the Python tokenizer and the reference translations. Skipped unless
// MARIAN_DIR is set: a folder with one sub-folder per direction (he-en, en-he)
// plus ref.json (per direction: text,
// Python's input ids, reference translation).
//
//   MARIAN_DIR=/path MARIAN_PACK=/folder-of-mt-files LD_LIBRARY_PATH=.../sherpa_onnx_linux-2.0.1/linux/x64 flutter test test/marian_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:translatorai/src/chrf.dart';
import 'package:translatorai/src/marian.dart';
import 'package:translatorai/src/opus_engine.dart';
import 'package:translatorai/src/translator.dart';

void main() {
  final dir = Platform.environment['MARIAN_DIR'];
  final skip = dir == null ? 'set MARIAN_DIR' : false;
  // the files as the app stores them (mt-<from>-<to>-…, one folder)
  packRouting(Platform.environment['MARIAN_PACK']);

  for (final d in const ['he-en', 'en-he']) {
    test('$d: same token ids as Python, and the translation scores', () {
      final ref = (jsonDecode(File('$dir/ref.json').readAsStringSync())[d] as List).cast<Map<String, dynamic>>();
      final sw = Stopwatch()..start();
      final m = MarianModel.load('$dir/$d');
      // ignore: avoid_print
      print('$d load ${sw.elapsedMilliseconds} ms');
      var same = 0;
      for (final r in ref) {
        if (m.encode(r['text'] as String).join(',') == (r['ids'] as List).join(',')) {
          same++;
        } else {
          // ignore: avoid_print
          print('ids differ: ${r['text']}\n  dart ${m.encode(r['text'] as String)}\n  py   ${r['ids']}');
        }
      }
      sw.reset();
      final hyp = [for (final r in ref) m.translate(r['text'] as String)];
      final ms = sw.elapsedMilliseconds / ref.length;
      final score = chrF(hyp, [for (final r in ref) r['ref'] as String]);
      // ignore: avoid_print
      print('$d ids same $same/${ref.length}  chrF ${score.toStringAsFixed(1)}  ${ms.round()} ms/sentence\n  e.g. ${hyp.first}');
      m.release();
      expect(same, greaterThanOrEqualTo(ref.length * 0.95));
      expect(score, greaterThan(d == 'he-en' ? 67 : 56));
    }, skip: skip, timeout: Timeout.none);
  }
}

/// ML Kit's stand-in: marks what it translated.
class _Fake extends TranslationEngine {
  final calls = <String>[];
  @override
  String get name => 'fake';
  @override
  Set<String> get languages => {'he', 'en', 'ru'};
  @override
  Future<bool> isReady(String code) async => false;
  @override
  Future<void> prepare(String code) async => calls.add('prepare $code');
  @override
  Future<String> translate(String text, {required String from, required String to}) async {
    calls.add('$from>$to');
    return '[$to] $text';
  }

  @override
  Future<void> delete(String code) async {}
  @override
  Future<void> close() async {}
}

void packRouting(String? pack) {
  test('the pack translates its directions, goes through English for the rest, and leaves other pairs to ML Kit', () async {
    final fake = _Fake();
    final e = PackEngine(fallback: fake, installed: (d) => true, pathOf: (n) => '$pack/$n');
    expect(await e.translate('שלום, מה שלומך?', from: 'he', to: 'en'), isNot(contains('[')));
    expect(fake.calls, isEmpty);
    final ru = await e.translate('שלום, מה שלומך?', from: 'he', to: 'ru');
    expect(ru, startsWith('[ru] '));
    expect(ru, isNot(contains('ש'))); // Hebrew went to English first
    expect(fake.calls, ['en>ru']);
    expect(await e.translate('Привет', from: 'ru', to: 'he'), contains(RegExp('[א-ת]')));
    expect(fake.calls, ['en>ru', 'ru>en']);
    await e.translate('Hola', from: 'es', to: 'fr');
    expect(fake.calls.last, 'es>fr');
    expect(await e.isReady('he'), isTrue);
    await e.prepare('he');
    expect(fake.calls, isNot(contains('prepare he')));
    final none = PackEngine(fallback: fake, installed: (d) => false, pathOf: (n) => '$pack/$n');
    await none.translate('שלום', from: 'he', to: 'en');
    expect(fake.calls.last, 'he>en');
    expect(none.name, 'fake');
    await e.close();
  }, skip: pack == null ? 'set MARIAN_PACK' : false, timeout: Timeout.none);
}
