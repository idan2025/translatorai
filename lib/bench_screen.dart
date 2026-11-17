import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/chrf.dart';
import 'src/languages.dart';
import 'src/translator.dart';

/// Scores the on-device translator on 60 sentences that exist in Hebrew, English
/// and Russian (Google FLEURS, CC-BY 4.0), with the same chrF used on a desktop,
/// so the engine's quality can be compared with other engines by number rather
/// than by feel. Needs the Hebrew and Russian translation models (~30 MB each).
class TranslationBenchmark extends StatefulWidget {
  const TranslationBenchmark({super.key, required this.engines});

  /// Each engine is scored on the same sentences, side by side (the app's
  /// engine, and ML Kit alone when a translation pack is installed).
  final List<TranslationEngine> engines;
  @override
  State<TranslationBenchmark> createState() => _TranslationBenchmarkState();
}

class _Row {
  _Row(this.engine, this.from, this.to);
  final TranslationEngine engine;
  final String from, to;
  double? score;
  double? msPerSentence;
  List<String> output = [];
}

class _TranslationBenchmarkState extends State<TranslationBenchmark> {
  late final rows = [
    for (final e in widget.engines)
      for (final p in const [('he', 'en'), ('en', 'he'), ('ru', 'en'), ('en', 'ru'), ('he', 'ru'), ('ru', 'he')]) _Row(e, p.$1, p.$2)
  ];
  late String status = 'Ready. Runs 6 directions × 60 sentences${widget.engines.length > 1 ? ' for each engine' : ''}, about a minute each.';
  bool running = false;
  List<Map<String, dynamic>> sentences = [];

  Future<void> run() async {
    setState(() {
      running = true;
      status = 'Loading sentences…';
    });
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/bench/sentences.json')) as Map<String, dynamic>;
      sentences = (raw['sentences'] as List).cast<Map<String, dynamic>>();
      for (final e in widget.engines) {
        for (final c in const ['he', 'ru', 'en']) {
          setState(() => status = 'Preparing the ${nameOf(c)} translation model (downloads once)…');
          await e.prepare(c);
        }
      }
      for (final r in rows) {
        setState(() => status = '${r.engine.name}: translating ${nameOf(r.from)} → ${nameOf(r.to)}…');
        final sw = Stopwatch()..start();
        final out = <String>[];
        for (final s in sentences) {
          out.add(await r.engine.translate(s[r.from] as String, from: r.from, to: r.to));
        }
        sw.stop();
        r.output = out;
        r.msPerSentence = sw.elapsedMilliseconds / sentences.length;
        r.score = chrF(out, [for (final s in sentences) s[r.to] as String]);
        setState(() {});
      }
      status = 'Done. Copy the results and send them.';
    } catch (e) {
      status = 'Failed: $e';
    }
    if (mounted) setState(() => running = false);
  }

  void copy() {
    final data = {
      'metric': 'chrF (sacreBLEU defaults), 60 FLEURS sentences',
      'results': [
        for (final r in rows)
          if (r.score != null)
            {'engine': r.engine.name, 'pair': '${r.from}-${r.to}', 'chrF': double.parse(r.score!.toStringAsFixed(1)), 'ms_per_sentence': r.msPerSentence!.round(), 'output': r.output}
      ],
    };
    Clipboard.setData(ClipboardData(text: jsonEncode(data)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final done = rows.any((r) => r.score != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Translation quality test')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(status),
        const SizedBox(height: 16),
        for (final r in rows) ...[
          if (r == rows.firstWhere((x) => x.engine == r.engine))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(r.engine.name, style: Theme.of(context).textTheme.titleMedium),
            ),
          ListTile(
            title: Text('${nameOf(r.from)} → ${nameOf(r.to)}'),
            subtitle: r.msPerSentence == null ? null : Text('${r.msPerSentence!.round()} ms per sentence'),
            trailing: r.score == null
                ? const Text('—')
                : Text('chrF ${r.score!.toStringAsFixed(1)}', style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: running ? null : run,
          icon: running ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
          label: Text(running ? 'Running…' : 'Run the test'),
        ),
        if (done)
          OutlinedButton.icon(onPressed: copy, icon: const Icon(Icons.copy), label: const Text('Copy results')),
        const SizedBox(height: 16),
        Text('chrF is a 0–100 score of how many character sequences a translation shares with a human one; '
            'higher is better. Sentences: Google FLEURS (CC-BY 4.0).',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
