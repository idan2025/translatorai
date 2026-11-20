import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ort.dart';
import 'spm.dart';

/// One translation direction of a pack, run with ONNX Runtime. Two graph layouts:
/// Opus-MT's (Marian, exported by optimum: attention masks and a cross-attention
/// cache) and the plain one of the quickmt pack (`cross_cache: false` in its
/// config: no masks, the decoder recomputes cross attention from the encoder
/// output, only the self-attention cache travels, source and target have their
/// own vocabularies and no `</s>` ends the source). The Marian note follows.
///
/// An Opus-MT (Marian) direction is: an
/// encoder and a decoder with its attention cache, int8. Greedy decoding:
/// measured on 60 FLEURS sentences it scores within 0.2 chrF of the full
/// PyTorch model with 4-beam search (he→en 68.7 vs 68.9, en→he 57.5 vs 57.7)
/// at a fraction of the time.
///
/// Synchronous and heavy: run it off the UI thread ([TranslateWorker]).
class MarianModel {
  MarianModel._(this._enc, this._dec, this._src, this._vocab, this._pieces, this._layers, this._heads, this._dim,
      this._start, this._eos, this._pad, this._unk, this._plain, this._srcEos);

  /// Loads a direction from [dir], which holds `encoder.int8.onnx`,
  /// `decoder.int8.onnx`, `source.spm`, `vocab.json` and
  /// `config.json` (file names may carry a [prefix]).
  factory MarianModel.load(String dir, {String prefix = '', int threads = 4}) {
    String f(String name) => '$dir/$prefix$name';
    final cfg = jsonDecode(File(f('config.json')).readAsStringSync()) as Map<String, dynamic>;
    final vocab = (jsonDecode(File(f('vocab.json')).readAsStringSync()) as Map<String, dynamic>).cast<String, int>();
    // a pack with its own target vocabulary (quickmt) names it; Marian's one vocabulary serves both sides
    final targetFile = File(f('target-vocab.json'));
    final target = targetFile.existsSync()
        ? (jsonDecode(targetFile.readAsStringSync()) as Map<String, dynamic>).cast<String, int>()
        : vocab;
    final pieces = <int, String>{for (final e in target.entries) e.value: e.key};
    final ort = Ort.instance;
    return MarianModel._(
      ort.load(f('encoder.int8.onnx'), threads: threads),
      ort.load(f('decoder.int8.onnx'), threads: threads),
      SentencePiece.fromBytes(File(f('source.spm')).readAsBytesSync()),
      vocab,
      pieces,
      cfg['decoder_layers'] as int,
      cfg['decoder_attention_heads'] as int,
      (cfg['d_model'] as int) ~/ (cfg['decoder_attention_heads'] as int),
      cfg['decoder_start_token_id'] as int,
      cfg['eos_token_id'] as int,
      cfg['pad_token_id'] as int,
      vocab['<unk>'] ?? 1,
      cfg['cross_cache'] == false,
      cfg['source_eos'] != false,
    );
  }

  final OrtSession _enc, _dec;
  final SentencePiece _src; // output pieces come from the shared vocabulary, so no target model is read
  final Map<String, int> _vocab;
  final Map<int, String> _pieces;
  final int _layers, _heads, _dim, _start, _eos, _pad, _unk;

  /// The plain graph layout (no masks, no cross-attention cache), and whether
  /// the source ends in `</s>`.
  final bool _plain, _srcEos;

  /// The ids the encoder reads for [text], ending in `</s>` (Marian).
  List<int> encode(String text) {
    final ids = [for (final p in _src.encode(text)) _vocab[p] ?? _unk];
    // the model has 512 positions; a longer input (a very long monologue) is cut
    return [...ids.length > 511 ? ids.sublist(0, 511) : ids, if (_srcEos) _eos];
  }

  /// Longest output, in tokens, for an input of [n] tokens: a runaway loop stops here.
  static int maxLength(int n) => 16 + n * 3;

  String translate(String text) {
    if (text.trim().isEmpty) return text;
    final ids = encode(text);
    final ort = Ort.instance;
    final input = ort.int64(ids, [1, ids.length]);
    final mask = _plain ? null : ort.int64(List.filled(ids.length, 1), [1, ids.length]);
    final hidden = _enc.run({'input_ids': input, 'attention_mask': ?mask}, const ['last_hidden_state']).single;
    input.release();
    // the caches that travel between steps: all four kinds (Marian) or the self-attention pair (plain)
    final kinds = _plain ? const ['decoder.key', 'decoder.value'] : const ['decoder.key', 'decoder.value', 'encoder.key', 'encoder.value'];

    final empty = Float32List(0);
    final past = <String, OrtValue>{
      for (var l = 0; l < _layers; l++)
        for (final k in kinds) 'past_key_values.$l.$k': ort.float32(empty, [1, _heads, 0, _dim]),
    };
    final outNames = <String>[
      'logits',
      for (var l = 0; l < _layers; l++)
        for (final k in kinds) 'present.$l.$k',
    ];
    final out = <int>[];
    var last = _start;
    try {
      for (var step = 0; step < maxLength(ids.length); step++) {
        final first = step == 0;
        final tok = ort.int64([last], const [1, 1]);
        final branch = _plain ? null : ort.boolean(!first);
        final r = _dec.run({
          'input_ids': tok,
          'encoder_hidden_states': hidden,
          'encoder_attention_mask': ?mask,
          'use_cache_branch': ?branch,
          ...past,
        }, outNames);
        tok.release();
        branch?.release();
        final logits = r[0].floats();
        final vocabSize = logits.length; // [1, 1, vocab]
        var best = -1;
        var bestScore = double.negativeInfinity;
        for (var v = 0; v < vocabSize; v++) {
          if (v == _pad) continue;
          if (logits[v] > bestScore) {
            bestScore = logits[v];
            best = v;
          }
        }
        r[0].release();
        // keep the self-attention cache from every step, the cross-attention one from the first
        for (var i = 1; i < r.length; i++) {
          final key = outNames[i].replaceFirst('present', 'past_key_values');
          if (first || key.contains('.decoder.')) {
            past.remove(key)?.release();
            past[key] = r[i];
          } else {
            r[i].release();
          }
        }
        if (best == _eos) break;
        out.add(best);
        last = best;
      }
    } finally {
      for (final v in past.values) {
        v.release();
      }
      hidden.release();
      mask?.release();
    }
    return SentencePiece.decode([
      for (final id in out)
        if (_pieces[id] case final p? when !p.startsWith('<')) p, // ignore: use_null_aware_elements
    ]);
  }

  void release() {
    _enc.release();
    _dec.release();
  }
}
