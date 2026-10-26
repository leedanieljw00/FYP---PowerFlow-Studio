import 'dart:math' as math;

import '../utils/format.dart';

/// An immutable complex number `z = re + j·im`.
///
/// Uses the electrical-engineering convention where the imaginary unit is
/// written `j`. Every operation returns a new instance.
class Complex {
  /// Creates a complex number from rectangular (Cartesian) components.
  const Complex(this.re, [this.im = 0.0]);

  /// Creates a complex number from polar form `magnitude ∠ angleRad`.
  factory Complex.polar(double magnitude, double angleRad) =>
      Complex(magnitude * math.cos(angleRad), magnitude * math.sin(angleRad));

  /// Creates a complex number from polar form with the angle in degrees.
  factory Complex.polarDeg(double magnitude, double angleDeg) =>
      Complex.polar(magnitude, angleDeg * kRadPerDeg);

  /// Real part.
  final double re;

  /// Imaginary part.
  final double im;

  static const Complex zero = Complex(0.0, 0.0);
  static const Complex one = Complex(1.0, 0.0);
  static const Complex j = Complex(0.0, 1.0);

  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);

  Complex operator -(Complex other) => Complex(re - other.re, im - other.im);

  Complex operator -() => Complex(-re, -im);

  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);

  /// Complex division using Smith's algorithm (robust against overflow).
  ///
  /// Throws [ArgumentError] when dividing by zero.
  Complex operator /(Complex other) {
    final c = other.re;
    final d = other.im;
    if (c == 0.0 && d == 0.0) {
      throw ArgumentError('Complex division by zero');
    }
    if (c.abs() >= d.abs()) {
      final r = d / c;
      final den = c + d * r;
      return Complex((re + im * r) / den, (im - re * r) / den);
    } else {
      final r = c / d;
      final den = c * r + d;
      return Complex((re * r + im) / den, (im * r - re) / den);
    }
  }

  /// Multiplies by a real scalar.
  Complex scale(double k) => Complex(re * k, im * k);

  /// Complex conjugate `re − j·im`.
  Complex get conjugate => Complex(re, -im);

  /// `1 / z`.
  Complex get reciprocal => Complex.one / this;

  /// Magnitude `|z|` (overflow-safe hypotenuse).
  double get abs => _hypot(re, im);

  /// Squared magnitude `|z|²`.
  double get abs2 => re * re + im * im;

  /// Phase angle in radians, in `(−π, π]`. Returns 0 for `z = 0`.
  double get arg => (re == 0.0 && im == 0.0) ? 0.0 : math.atan2(im, re);

  /// Phase angle in degrees.
  double get argDeg => arg * kDegPerRad;

  bool get isZero => re == 0.0 && im == 0.0;

  bool get isFinite => re.isFinite && im.isFinite;

  bool get isNaN => re.isNaN || im.isNaN;

  /// Component-wise comparison with an absolute [tolerance].
  bool approxEquals(Complex other, [double tolerance = 1e-9]) =>
      (re - other.re).abs() <= tolerance && (im - other.im).abs() <= tolerance;

  /// Rectangular string, e.g. `20.0000 − j50.0000`.
  String toCartesianString([int digits = 4]) {
    final imText = fmtNum(im.abs(), digits);
    final negative = im < 0 && double.parse(imText) != 0;
    return '${fmtNum(re, digits)} ${negative ? '−' : '+'} j$imText';
  }

  /// Polar string, e.g. `53.8516 ∠ −68.1986°`.
  String toPolarString([int digits = 4]) =>
      '${fmtNum(abs, digits)} ∠ ${fmtNum(argDeg, digits)}°';

  @override
  bool operator ==(Object other) =>
      other is Complex && other.re == re && other.im == im;

  @override
  int get hashCode => Object.hash(re, im);

  @override
  String toString() => toCartesianString();
}

double _hypot(double a, double b) {
  var x = a.abs();
  var y = b.abs();
  if (x < y) {
    final t = x;
    x = y;
    y = t;
  }
  if (x == 0.0) return 0.0;
  final r = y / x;
  return x * math.sqrt(1.0 + r * r);
}
