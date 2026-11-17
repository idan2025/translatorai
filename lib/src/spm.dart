import 'dart:convert';
import 'dart:typed_data';

/// A SentencePiece unigram tokenizer read straight from a `.spm` model file
/// (the protobuf `ModelProto`), the way Opus-MT's Marian models cut text.
///
/// Segmentation is the unigram model's own: the split whose pieces' scores add
/// up highest (Viterbi). Normalisation is simplified: the model's precompiled
/// NFKC map is not applied, only its whitespace rules (trim, collapse, a `▁`
/// before every word). Speech-recogniser output is plain text, where NFKC
/// changes nothing; `test/marian_test.dart` checks the ids against the Python
/// tokenizer on real sentences.
class SentencePiece {
  SentencePiece._(this._pieces, this._scores, this._types, this._addDummyPrefix, this._removeExtraSpaces) {
    for (var i = 0; i < _pieces.length; i++) {
      if (_types[i] == _normal || _types[i] == _userDefined) {
        _index[_pieces[i]] = i;
        final n = _pieces[i].runes.length;
        if (n > _maxLen) _maxLen = n;
      }
    }
    var min = 0.0;
    for (final s in _scores) {
      if (s < min) min = s;
    }
    _unkScore = min - 10;
  }

  static const _normal = 1, _unknown = 2, _userDefined = 4;

  final List<String> _pieces;
  final List<double> _scores;
  final List<int> _types;
  final bool _addDummyPrefix, _removeExtraSpaces;
  final _index = <String, int>{};
  var _maxLen = 1;
  late final double _unkScore;

  static const space = '▁'; // ▁

  /// Parses a `.spm` file's bytes.
  factory SentencePiece.fromBytes(Uint8List bytes) {
    final pieces = <String>[], scores = <double>[], types = <int>[];
    var dummy = true, extra = true;
    final r = _Proto(bytes);
    while (!r.done) {
      final (field, wire) = r.tag();
      if (field == 1 && wire == 2) {
        final m = _Proto(r.bytes());
        var piece = '', score = 0.0, type = _normal;
        while (!m.done) {
          final (f, w) = m.tag();
          if (f == 1 && w == 2) {
            piece = utf8.decode(m.bytes());
          } else if (f == 2 && w == 5) {
            score = m.float32();
          } else if (f == 3 && w == 0) {
            type = m.varint();
          } else {
            m.skip(w);
          }
        }
        pieces.add(piece);
        scores.add(score);
        types.add(type);
      } else if (field == 3 && wire == 2) {
        final m = _Proto(r.bytes());
        while (!m.done) {
          final (f, w) = m.tag();
          if (f == 3 && w == 0) {
            dummy = m.varint() != 0;
          } else if (f == 4 && w == 0) {
            extra = m.varint() != 0;
          } else {
            m.skip(w);
          }
        }
      } else {
        r.skip(wire);
      }
    }
    return SentencePiece._(pieces, scores, types, dummy, extra);
  }

  String normalise(String text) {
    var t = text.replaceAll(RegExp(r'[\s ​  ﻿]+'), ' ');
    if (_removeExtraSpaces) t = t.trim();
    if (t.isEmpty) return '';
    if (_addDummyPrefix) t = ' $t';
    return t.replaceAll(' ', space);
  }

  /// The pieces of [text], best split first to last.
  List<String> encode(String text) {
    final chars = normalise(text).runes.map(String.fromCharCode).toList();
    final n = chars.length;
    if (n == 0) return const [];
    final best = List<double>.filled(n + 1, double.negativeInfinity);
    final from = List<int>.filled(n + 1, -1);
    best[0] = 0;
    for (var i = 0; i < n; i++) {
      if (best[i] == double.negativeInfinity) continue;
      var piece = '';
      var matched = false;
      for (var j = i; j < n && j - i < _maxLen; j++) {
        piece += chars[j];
        final id = _index[piece];
        if (id == null) continue;
        matched |= j == i;
        final s = best[i] + _scores[id];
        if (s > best[j + 1]) {
          best[j + 1] = s;
          from[j + 1] = i;
        }
      }
      if (!matched) {
        // a character no piece covers: it becomes the unknown piece on its own
        final s = best[i] + _unkScore;
        if (s > best[i + 1]) {
          best[i + 1] = s;
          from[i + 1] = i;
        }
      }
    }
    final out = <String>[];
    for (var k = n; k > 0; k = from[k]) {
      out.add(chars.sublist(from[k], k).join());
    }
    return out.reversed.toList();
  }

  /// Pieces back to text.
  static String decode(Iterable<String> pieces) => pieces.join().replaceAll(space, ' ').trim();

  bool isUnknownType(int id) => _types[id] == _unknown;
}

/// Just enough protobuf reading for a SentencePiece model.
class _Proto {
  _Proto(this._b);
  final Uint8List _b;
  var _i = 0;
  bool get done => _i >= _b.length;

  int varint() {
    var shift = 0, v = 0;
    while (true) {
      final x = _b[_i++];
      v |= (x & 0x7f) << shift;
      if (x < 0x80) return v;
      shift += 7;
    }
  }

  (int, int) tag() {
    final t = varint();
    return (t >> 3, t & 7);
  }

  Uint8List bytes() {
    final n = varint();
    final out = Uint8List.sublistView(_b, _i, _i + n);
    _i += n;
    return out;
  }

  double float32() {
    final v = ByteData.sublistView(_b, _i, _i + 4).getFloat32(0, Endian.little);
    _i += 4;
    return v;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _i += 8;
      case 2:
        final n = varint(); // not `_i += varint()`: that adds to _i as it was before the length was read
        _i += n;
      case 5:
        _i += 4;
      default:
        throw FormatException('protobuf wire type $wire');
    }
  }
}
