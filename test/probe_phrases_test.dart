// Prints the quickmt pack's translation of every line of PROBE_FILE (one phrase per
// line), for finding words it gets wrong. Skipped unless MQ_DIR and PROBE_FILE are set.
//
//   MQ_DIR=/path PROBE_FILE=he.txt PROBE_DIR=he-en LD_LIBRARY_PATH=.../linux/x64 flutter test test/probe_phrases_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:translatorai/src/marian.dart';

void main() {
  final env = Platform.environment;
  final skip = env['MQ_DIR'] == null || env['PROBE_FILE'] == null ? 'set MQ_DIR and PROBE_FILE' : false;
  test('probe phrases', () {
    final m = MarianModel.load('${env['MQ_DIR']}/${env['PROBE_DIR'] ?? 'he-en'}');
    final out = StringBuffer();
    for (final l in File(env['PROBE_FILE']!).readAsLinesSync()) {
      if (l.trim().isEmpty) continue;
      out.writeln('$l\t${m.translate(l)}');
    }
    File(env['PROBE_OUT'] ?? '/dev/stdout').writeAsStringSync(out.toString());
    m.release();
  }, skip: skip, timeout: Timeout.none);
}
