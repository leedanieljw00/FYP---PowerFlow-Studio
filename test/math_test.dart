import 'package:flutter_test/flutter_test.dart';
import 'package:powerflow_studio/core/math/complex.dart';
import 'package:powerflow_studio/core/math/gauss_seidel.dart';
import 'package:powerflow_studio/core/math/matrix.dart';
import 'package:powerflow_studio/core/math/newton_raphson.dart';
import 'package:powerflow_studio/core/math/ybus_builder.dart';

void main() {
  group('Complex Numbers', () {
    test('Basic arithmetic & Smith division', () {
      const z1 = Complex(3.0, 4.0);
      const z2 = Complex(1.0, 2.0);

      expect(z1.abs, closeTo(5.0, 1e-9));
      expect(z1 + z2, equals(const Complex(4.0, 6.0)));
      expect(z1 - z2, equals(const Complex(2.0, 2.0)));
      expect(z1 * z2, equals(const Complex(-5.0, 10.0)));

      final div = z1 / z2;
      // (3+j4)/(1+j2) = (3+j4)(1-j2)/5 = (3-j6+j4+8)/5 = (11-j2)/5 = 2.2 - j0.4
      expect(div.re, closeTo(2.2, 1e-9));
      expect(div.im, closeTo(-0.4, 1e-9));
    });

    test('Polar conversions', () {
      final p = Complex.polarDeg(2.0, 60.0);
      expect(p.re, closeTo(1.0, 1e-9));
      expect(p.im, closeTo(1.7320508, 1e-6));
      expect(p.argDeg, closeTo(60.0, 1e-6));
    });
  });

  group('Linear Algebra / Matrix', () {
    test('Matrix solve Ax = b and inversion', () {
      final a = RealMatrix.fromRows([
        [2.0, 1.0, -1.0],
        [-3.0, -1.0, 2.0],
        [-2.0, 1.0, 2.0],
      ]);
      final b = [8.0, -11.0, -3.0];
      final x = a.solve(b);

      // Expected solution: x1 = 2, x2 = 3, x3 = -1
      expect(x[0], closeTo(2.0, 1e-9));
      expect(x[1], closeTo(3.0, 1e-9));
      expect(x[2], closeTo(-1.0, 1e-9));

      final inv = a.inverse();
      final prod = a * inv;
      expect(prod.approxEquals(RealMatrix.identity(3), 1e-9), isTrue);
    });
  });

  group('YBusBuilder', () {
    test('Builds correct 3-bus admittance matrix', () {
      // 3-Bus system with branches:
      // Line 1-2: z = 0.02 + j0.04, y = 1/(0.02+j0.04) = 10 - j20
      // Line 1-3: z = 0.01 + j0.03, y = 10 - j30
      // Line 2-3: z = 0.0125 + j0.025, y = 16 - j32
      final lines = [
        const BranchParams(from: 0, to: 1, r: 0.02, x: 0.04),
        const BranchParams(from: 0, to: 2, r: 0.01, x: 0.03),
        const BranchParams(from: 1, to: 2, r: 0.0125, x: 0.025),
      ];

      final ybus = YBusBuilder.build(3, lines);
      expect(ybus.rows, equals(3));
      expect(ybus.cols, equals(3));
      expect(ybus.isSymmetric(), isTrue);

      // Y12 = -y12 = -(10 - j20) = -10 + j20
      expect(ybus.get(0, 1).re, closeTo(-10.0, 1e-6));
      expect(ybus.get(0, 1).im, closeTo(20.0, 1e-6));
    });
  });

  group('Power Flow Solvers (3-Bus Saadat Benchmark)', () {
    final buses = [
      const PfBus(
        type: BusType.slack,
        vMag: 1.05,
        angle: 0.0,
      ),
      const PfBus(
        type: BusType.pv,
        vMag: 1.04,
        angle: 0.0,
        pGen: 0.50,
        qMin: -0.50,
        qMax: 1.00,
      ),
      const PfBus(
        type: BusType.pq,
        vMag: 1.00,
        angle: 0.0,
        pLoad: 1.00,
        qLoad: 0.50,
      ),
    ];

    final lines = [
      const BranchParams(from: 0, to: 1, r: 0.02, x: 0.04, bHalf: 0.015),
      const BranchParams(from: 0, to: 2, r: 0.01, x: 0.03, bHalf: 0.01),
      const BranchParams(from: 1, to: 2, r: 0.0125, x: 0.025, bHalf: 0.01),
    ];

    test('Newton-Raphson Solver converges to high precision', () {
      final ybus = YBusBuilder.build(3, lines);
      const solver = NewtonRaphsonSolver(
        options: SolverOptions(tolerance: 1e-4, maxIterations: 20),
      );

      final result = solver.solve(ybus: ybus, buses: buses, branches: lines);

      expect(result.converged, isTrue);
      expect(result.iterationCount, lessThanOrEqualTo(5));
      expect(result.finalPowerMismatch, lessThan(1e-4));

      // Bus 1 voltage = 1.05 pu
      expect(result.vMag[0], closeTo(1.05, 1e-4));
      // Bus 2 voltage = 1.04 pu
      expect(result.vMag[1], closeTo(1.04, 1e-4));
      // Bus 3 voltage ~ 1.00 pu
      expect(result.vMag[2], greaterThan(0.95));
      expect(result.vMag[2], lessThan(1.05));

      // Check line flows are non-empty
      expect(result.lineFlows.length, equals(3));
      expect(result.totalLoss.re, greaterThan(0.0)); // Non-zero positive losses
    });

    test('Gauss-Seidel Solver converges on same network', () {
      final ybus = YBusBuilder.build(3, lines);
      const solver = GaussSeidelSolver(
        options: SolverOptions(tolerance: 1e-4, maxIterations: 100),
      );

      final result = solver.solve(ybus: ybus, buses: buses, branches: lines);

      expect(result.converged, isTrue);
      // GS takes more iterations than NR but converges
      expect(result.iterationCount, greaterThan(2));
      // Results should match NR closely
      expect(result.vMag[0], closeTo(1.05, 1e-3));
      expect(result.vMag[1], closeTo(1.04, 1e-3));
    });
  });
}
