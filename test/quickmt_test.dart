// The quickmt Hebrew pack through the app's own ONNX Runtime binding and
// tokenizer, scored with chrF on FLEURS sentences. Skipped unless MQ_DIR is set:
// a folder with `he-en` and `en-he` sub-folders holding the pack's files
// without the `mq-<pair>-` prefix, and MQ_PAIRS: a JSON list of {"he": …, "en": …}.
//
//   MQ_DIR=/path MQ_PAIRS=/pairs.json LD_LIBRARY_PATH=.../sherpa_onnx_linux-2.0.1/linux/x64 flutter test test/quickmt_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:translatorai/src/chrf.dart';
import 'package:translatorai/src/marian.dart';

void main() {
  final dir = Platform.environment['MQ_DIR'], pairsFile = Platform.environment['MQ_PAIRS'];
  final skip = dir == null || pairsFile == null ? 'set MQ_DIR and MQ_PAIRS' : false;
  for (final d in const ['he-en', 'en-he']) {
    test('$d: the quickmt pack translates as well as it did in Python', () {
      final pairs = (jsonDecode(File(pairsFile!).readAsStringSync()) as List).cast<Map<String, dynamic>>();
      final from = d.substring(0, 2), to = d.substring(3);
      final m = MarianModel.load('$dir/$d');
      final sw = Stopwatch()..start();
      final hyp = [for (final p in pairs) m.translate(p[from] as String)];
      final ms = sw.elapsedMilliseconds / pairs.length;
      final score = chrF(hyp, [for (final p in pairs) p[to] as String]);
      // ignore: avoid_print
      print('$d chrF ${score.toStringAsFixed(1)}  ${ms.round()} ms/sentence  e.g. ${hyp.first}');
      m.release();
      expect(score, greaterThan(d == 'he-en' ? 67 : 62));
    }, skip: skip, timeout: Timeout.none);
  }
}
