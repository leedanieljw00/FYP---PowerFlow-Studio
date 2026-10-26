import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:powerflow_studio/core/utils/format.dart';

void main() {
  group('Angle Conversion Constants', () {
    test('kDegPerRad and kRadPerDeg are reciprocals and accurate', () {
      expect(kDegPerRad * kRadPerDeg, closeTo(1.0, 1e-12));
      expect(180.0 * kRadPerDeg, closeTo(math.pi, 1e-12));
      expect(math.pi * kDegPerRad, closeTo(180.0, 1e-12));
    });
  });

  group('fmtNum', () {
    test('formats normal floating numbers with specified decimal places', () {
      expect(fmtNum(3.1415926, 2), equals('3.14'));
      expect(fmtNum(3.1415926, 4), equals('3.1416'));
      expect(fmtNum(12.0, 3), equals('12.000'));
    });

    test('handles NaN and infinity gracefully', () {
      expect(fmtNum(double.nan), equals('NaN'));
      expect(fmtNum(double.infinity), equals('∞'));
      expect(fmtNum(double.negativeInfinity), equals('−∞'));
    });

    test('normalises negative zero to positive zero', () {
      expect(fmtNum(-0.00001, 2), equals('0.00'));
      expect(fmtNum(-0.0, 3), equals('0.000'));
    });
  });

  group('fmtSci', () {
    test('formats numbers in exponential scientific notation', () {
      expect(fmtSci(0.0), equals('0'));
      expect(fmtSci(1234.5, 2), equals('1.23e+3'));
      expect(fmtSci(0.000456, 2), equals('4.56e-4'));
    });

    test('delegates non-finite numbers to fmtNum', () {
      expect(fmtSci(double.nan), equals('NaN'));
      expect(fmtSci(double.infinity), equals('∞'));
    });
  });

  group('fmtAuto', () {
    test('uses fixed notation for standard engineering range [1e-3, 1e6)', () {
      expect(fmtAuto(0.05, 3), equals('0.050'));
      expect(fmtAuto(120.45, 2), equals('120.45'));
      expect(fmtAuto(0.0, 2), equals('0.00'));
    });

    test('switches to scientific notation for very small or large values', () {
      expect(fmtAuto(0.000045, 3), equals('4.50e-5'));
      expect(fmtAuto(5000000.0, 3), equals('5.00e+6'));
    });
  });

  group('sub (Unicode Subscripts)', () {
    test('converts positive integers to subscript characters', () {
      expect(sub(0), equals('₀'));
      expect(sub(1), equals('₁'));
      expect(sub(12), equals('₁₂'));
      expect(sub(4530), equals('₄₅₃₀'));
    });

    test('handles negative numbers with subscript minus sign', () {
      expect(sub(-1), equals('₋₁'));
      expect(sub(-42), equals('₋₄₂'));
    });
  });
}
