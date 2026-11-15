/// chrF, the character n-gram F-score used to compare translations (Popović
/// 2015), ported from sacreBLEU's defaults so a score measured on a phone is
/// comparable with one measured on a desktop: character n-grams up to order 6,
/// whitespace ignored, beta 2, corpus-level (match counts summed over all
/// sentences, then one score). 0 to 100, higher is better.
double chrF(List<String> hypotheses, List<String> references, {int order = 6, double beta = 2}) {
  assert(hypotheses.length == references.length);
  final hyp = List<int>.filled(order, 0), ref = List<int>.filled(order, 0), match = List<int>.filled(order, 0);
  for (var i = 0; i < hypotheses.length; i++) {
    final h = _chars(hypotheses[i]), r = _chars(references[i]);
    for (var n = 1; n <= order; n++) {
      final hg = _grams(h, n), rg = _grams(r, n);
      hyp[n - 1] += hg.values.fold(0, (a, b) => a + b);
      ref[n - 1] += rg.values.fold(0, (a, b) => a + b);
      hg.forEach((k, c) {
        final rc = rg[k];
        if (rc != null) match[n - 1] += c < rc ? c : rc;
      });
    }
  }
  var avgP = 0.0, avgR = 0.0, used = 0;
  for (var n = 0; n < order; n++) {
    if (hyp[n] > 0 && ref[n] > 0) {
      avgP += match[n] / hyp[n];
      avgR += match[n] / ref[n];
      used++;
    }
  }
  if (used == 0) return 0;
  avgP /= used;
  avgR /= used;
  if (avgP + avgR == 0) return 0;
  final f = beta * beta;
  return 100 * (1 + f) * avgP * avgR / (f * avgP + avgR);
}

/// Code points with all whitespace removed.
List<int> _chars(String s) => s.runes.where((c) => !RegExp(r'\s').hasMatch(String.fromCharCode(c))).toList();

Map<String, int> _grams(List<int> c, int n) {
  final out = <String, int>{};
  for (var i = 0; i + n <= c.length; i++) {
    final g = String.fromCharCodes(c.sublist(i, i + n));
    out[g] = (out[g] ?? 0) + 1;
  }
  return out;
}
