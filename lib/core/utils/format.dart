import 'dart:math' as math;

/// Degrees per radian.
const double kDegPerRad = 180.0 / math.pi;

/// Radians per degree.
const double kRadPerDeg = math.pi / 180.0;

/// Formats [v] with a fixed number of decimals, normalising `-0.000` to `0.000`.
String fmtNum(double v, [int digits = 4]) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? '∞' : '−∞';
  final s = v.toStringAsFixed(digits);
  if (double.parse(s) == 0) return 0.0.toStringAsFixed(digits);
  return s;
}

/// Formats [v] in scientific notation (e.g. `1.234e-5`).
String fmtSci(double v, [int digits = 3]) {
  if (!v.isFinite) return fmtNum(v);
  if (v == 0) return '0';
  return v.toStringAsExponential(digits);
}

/// Fixed notation for "normal" magnitudes, scientific for very small/large.
String fmtAuto(double v, [int digits = 4]) {
  final a = v.abs();
  if (a == 0 || (a >= 1e-3 && a < 1e6)) return fmtNum(v, digits);
  return fmtSci(v, digits - 1);
}

const String _subscriptDigits = '₀₁₂₃₄₅₆₇₈₉';

/// Converts an integer into Unicode subscript digits, e.g. `12` → `₁₂`.
String sub(int n) {
  final buffer = StringBuffer();
  for (final ch in n.toString().split('')) {
    buffer.write(ch == '-' ? '₋' : _subscriptDigits[int.parse(ch)]);
  }
  return buffer.toString();
}
