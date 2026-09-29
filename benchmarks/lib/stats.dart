/// Every timed benchmark keeps EVERY round, not the fastest one, and reports
/// the median with its range. Two variants are a TIE when their ranges
/// overlap: the harness says so itself, instead of a reader having to know
/// the machine's noise to discount a 3% difference.
class Sample {
  Sample(List<double> rounds) : rounds = List.unmodifiable(rounds) {
    if (rounds.isEmpty) throw ArgumentError('a sample needs rounds');
  }
  final List<double> rounds;

  double get median {
    final s = [...rounds]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  double get min => rounds.reduce((a, b) => a < b ? a : b);
  double get max => rounds.reduce((a, b) => a > b ? a : b);

  /// Half the range over the median — one number for "how noisy".
  double get spread => median == 0 ? 0 : (max - min) / 2 / median;

  Map<String, Object> toJson(String unit) => {
    unit: _r(median),
    'min': _r(min),
    'max': _r(max),
    'spread': _r(spread),
    'rounds': [for (final r in rounds) _r(r)],
  };
}

double _r(double v) => double.parse(v.toStringAsFixed(3));

/// Pairwise verdicts for a set of variants measuring the same thing, lower
/// is better: sorted by median, each adjacent pair is either a tie (ranges
/// overlap) or "A faster than B by x%".
List<Map<String, Object>> compare(Map<String, Sample> variants) {
  final sorted = variants.entries.toList()
    ..sort((a, b) => a.value.median.compareTo(b.value.median));
  final out = <Map<String, Object>>[];
  for (var i = 0; i + 1 < sorted.length; i++) {
    final a = sorted[i], b = sorted[i + 1];
    final overlap = a.value.max >= b.value.min;
    out.add({
      'faster': a.key,
      'slower': b.key,
      'verdict': overlap ? 'tie' : 'faster',
      'byPercent': _r((b.value.median - a.value.median) / b.value.median * 100),
      'reason': overlap
          ? 'ranges overlap (${_r(a.value.min)}–${_r(a.value.max)} vs '
                '${_r(b.value.min)}–${_r(b.value.max)})'
          : 'ranges do not overlap',
    });
  }
  return out;
}
