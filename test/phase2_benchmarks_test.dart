import 'package:flutter_test/flutter_test.dart';
import 'package:powerflow_studio/core/math/economic_dispatch/generator_model.dart';
import 'package:powerflow_studio/core/math/economic_dispatch/loss_dispatch.dart';
import 'package:powerflow_studio/core/math/economic_dispatch/lossless_dispatch.dart';
import 'package:powerflow_studio/core/math/load_frequency_control/droop_solver.dart';
import 'package:powerflow_studio/core/math/load_frequency_control/lfc_models.dart';
import 'package:powerflow_studio/core/math/load_frequency_control/two_area_lfc.dart';

void main() {
  group('EE4530 Generation Control & LFC Benchmarks', () {
    test('Example 2.3 & Tutorial 4 Q1: Dual-unit parallel droop sharing (R1=6%, R2=4%, ΔPL=90 MW)', () {
      // Two generators connected in parallel to a common system base of 1000 MVA at 50 Hz.
      // Unit 1: R1 = 6% = 0.06 pu on 1000 MVA base
      // Unit 2: R2 = 4% = 0.04 pu on 1000 MVA base
      // Load damping D = 0
      // Disturbance: ΔP_L = 90 MW (0.09 pu)
      final area = LfcArea(
        id: 'area_1',
        name: 'NTU Power Grid Area',
        systemMvaBase: 1000.0,
        nominalFreq: 50.0,
        dampingD: 0.0,
        generators: const [
          LfcGenerator(
            id: 'g1',
            name: 'Generator 1 (R1=6%)',
            mvaBase: 1000.0,
            droopR: 0.06,
          ),
          LfcGenerator(
            id: 'g2',
            name: 'Generator 2 (R2=4%)',
            mvaBase: 1000.0,
            droopR: 0.04,
          ),
        ],
      );

      // Solve static droop
      final result = DroopSolver.solveSteadyState(area: area, deltaPL_MW: 90.0);

      // 1/R1 = 1/0.06 = 16.6667
      // 1/R2 = 1/0.04 = 25.0
      // beta_sys = 16.6667 + 25.0 = 41.6667 pu
      expect(result.betaSys, closeTo(41.6667, 1e-3));

      // Δf = -ΔP_L / beta = -0.09 / 41.6667 = -0.00216 pu
      expect(result.deltaF_pu, closeTo(-0.00216, 1e-5));

      // At 50 Hz: Δf = -0.00216 * 50 = -0.108 Hz
      expect(result.deltaF_Hz, closeTo(-0.108, 1e-3));
      expect(result.fFinal_Hz, closeTo(49.892, 1e-3));

      // Generator sharing:
      // Unit 1 pickup: ΔP_m1 = -Δf / R1 = 0.00216 / 0.06 = 0.036 pu = 36 MW
      // Unit 2 pickup: ΔP_m2 = -Δf / R2 = 0.00216 / 0.04 = 0.054 pu = 54 MW
      final p1 = result.generatorResponses.firstWhere((r) => r.generatorId == 'g1');
      final p2 = result.generatorResponses.firstWhere((r) => r.generatorId == 'g2');

      expect(p1.deltaP_MW, closeTo(36.0, 1e-2));
      expect(p2.deltaP_MW, closeTo(54.0, 1e-2));
      expect(p1.deltaP_MW + p2.deltaP_MW, closeTo(90.0, 1e-2));

      // Participation ratio: p2 picks up 60%, p1 picks up 40%
      expect(p1.participationFactor, closeTo(0.40, 1e-3));
      expect(p2.participationFactor, closeTo(0.60, 1e-3));
    });

    test('EE4530 Assignment 1 Q1: Two-Area ACE and tie-line flow deviation (B1=12.5, B2=25, ACE1=-0.25, ACE2=0.10)', () {
      // Frequency bias constants: B1 = 12.5 pu/pu, B2 = 25.0 pu/pu
      // Measured Area Control Errors: ACE1 = -0.25 pu, ACE2 = 0.10 pu
      // Formulas from EE4530:
      // ACE1 = ΔP_tie1 + B1 * Δf
      // ACE2 = -ΔP_tie1 + B2 * Δf
      // => Δf = (ACE1 + ACE2) / (B1 + B2) = (-0.25 + 0.10) / (12.5 + 25.0) = -0.15 / 37.5 = -0.004 pu
      // => ΔP_tie1 = (B2 * ACE1 - B1 * ACE2) / (B1 + B2) = (25*(-0.25) - 12.5*(0.10)) / 37.5 = (-6.25 - 1.25) / 37.5 = -7.5 / 37.5 = -0.20 pu
      final inv = TwoAreaLfcSolver.solveFromAces(
        ace1: -0.25,
        ace2: 0.10,
        b1: 12.5,
        b2: 25.0,
      );

      expect(inv.deltaF_pu, closeTo(-0.004, 1e-6));
      expect(inv.deltaPtie1_pu, closeTo(-0.20, 1e-6));

      // Consistency check:
      // ACE1 = -0.20 + 12.5 * (-0.004) = -0.20 - 0.05 = -0.25 pu
      expect(inv.deltaPtie1_pu + 12.5 * inv.deltaF_pu, closeTo(-0.25, 1e-6));
      // ACE2 = -(-0.20) + 25.0 * (-0.004) = +0.20 - 0.10 = +0.10 pu
      expect(-inv.deltaPtie1_pu + 25.0 * inv.deltaF_pu, closeTo(0.10, 1e-6));
    });

    test('Two-Area Interconnected Grid tie-line flow under load disturbance', () {
      // Area 1: beta1 = 20 pu/pu
      // Area 2: beta2 = 30 pu/pu
      // Step load increase in Area 1 only: ΔP_L1 = 100 MW on 1000 MVA base = 0.1 pu
      final area1 = LfcArea(
        id: 'a1',
        name: 'Area 1',
        systemMvaBase: 1000.0,
        nominalFreq: 50.0,
        dampingD: 0.0,
        generators: const [
          LfcGenerator(id: 'g1', name: 'G1', mvaBase: 1000.0, droopR: 0.05), // 1/R = 20
        ],
      );

      final area2 = LfcArea(
        id: 'a2',
        name: 'Area 2',
        systemMvaBase: 1000.0,
        nominalFreq: 50.0,
        dampingD: 0.0,
        generators: const [
          LfcGenerator(id: 'g2', name: 'G2', mvaBase: 1000.0, droopR: 0.03333333), // 1/R = 30
        ],
      );

      final res = TwoAreaLfcSolver.solve(
        area1: area1,
        area2: area2,
        deltaPL1_MW: 100.0,
        deltaPL2_MW: 0.0,
      );

      // Δf = -0.1 / (20 + 30) = -0.002 pu
      expect(res.deltaF_pu, closeTo(-0.002, 1e-6));
      // Tie-line from Area 1 to 2: ΔP_tie1 = -0.1 * 30 / 50 = -0.06 pu = -60 MW
      // (Area 2 exports 60 MW into Area 1)
      expect(res.deltaPtie1_MW, closeTo(-60.0, 1e-4));
      // Area 1 ACE = -0.06 + 20*(-0.002) = -0.06 - 0.04 = -0.1 pu = -100 MW
      expect(res.ace1_MW, closeTo(-100.0, 1e-4));
      // Area 2 ACE = +0.06 + 30*(-0.002) = +0.06 - 0.06 = 0 MW (Area 2 sees ACE = 0!)
      expect(res.ace2_MW, closeTo(0.0, 1e-4));
    });
  });

  group('EE4530 Economic Dispatch Benchmarks', () {
    // EE4530 Tutorial 5 Q1 & Example 2.6:
    // Unit 1: C1 = 100 + 8.0*P1 + 0.008*P1^2, P1 in [100, 625] MW
    // Unit 2: C2 = 120 + 6.4*P2 + 0.0096*P2^2, P2 in [100, 625] MW
    // ICR1 = 8.0 + 0.016*P1
    // ICR2 = 6.4 + 0.0192*P2
    final unit1 = const GeneratorUnit(
      id: 'u1',
      name: 'Unit 1',
      alpha: 100.0,
      beta: 8.0,
      gamma: 0.008,
      pMin: 100.0,
      pMax: 625.0,
    );

    final unit2 = const GeneratorUnit(
      id: 'u2',
      name: 'Unit 2',
      alpha: 120.0,
      beta: 6.4,
      gamma: 0.0096,
      pMin: 100.0,
      pMax: 625.0,
    );

    test('Tutorial 5 Q1: Equal slope lossless dispatch at P_D = 800 MW', () {
      // Total demand = 800 MW
      // Without limits:
      // 1/(2*gamma1) = 1/0.016 = 62.5
      // beta1/(2*gamma1) = 8.0 * 62.5 = 500
      // 1/(2*gamma2) = 1/0.0192 = 52.0833
      // beta2/(2*gamma2) = 6.4 * 52.0833 = 333.3333
      // sum(1/2gamma) = 62.5 + 52.0833 = 114.5833
      // lambda = (800 + 500 + 333.3333) / 114.5833 = 1633.3333 / 114.5833 = 14.2545 $/MWh
      // P1 = (14.2545 - 8.0) / 0.016 = 390.91 MW
      // P2 = (14.2545 - 6.4) / 0.0192 = 409.09 MW
      // Both are within [100, 625], so no clamping required!
      final res = LosslessDispatchSolver.solve(
        units: [unit1, unit2],
        demand: 800.0,
        enforceLimits: true,
      );

      expect(res.isFeasible, isTrue);
      expect(res.clampedUnits.isEmpty, isTrue);
      expect(res.lambda, closeTo(14.2545, 1e-3));
      expect(res.powers['u1']!, closeTo(390.91, 1e-1));
      expect(res.powers['u2']!, closeTo(409.09, 1e-1));
      expect(res.powers['u1']! + res.powers['u2']!, closeTo(800.0, 1e-3));

      // Economic dispatch should save cost compared to equal allocation (400 MW each)
      expect(res.savings, greaterThan(0.0));
    });

    test('Limit clamping: P_D = 1235 MW forces Unit 1 to P_max (625 MW)', () {
      // Unconstrained lambda would yield P1 = 628.18 MW > 625 MW.
      // Unit 1 must be clamped at P_max = 625 MW.
      // Remaining demand = 1235 - 625 = 610 MW allocated to Unit 2.
      final res = LosslessDispatchSolver.solve(
        units: [unit1, unit2],
        demand: 1235.0,
        enforceLimits: true,
      );

      expect(res.isFeasible, isTrue);
      expect(res.powers['u1']!, closeTo(625.0, 1e-5)); // Unit 1 clamped at P_max
      expect(res.powers['u2']!, closeTo(610.0, 1e-5)); // Unit 2 carries remaining 610 MW
      expect(res.clampedUnits.containsKey('u1'), isTrue);
      expect(res.steps.length, greaterThan(1)); // Multi-step iteration verified!
    });

    test('Limit clamping: Unit 2 capped at 500 MW with P_D = 1100 MW', () {
      final unit2Capped = unit2.copyWith(pMax: 500.0);
      final res = LosslessDispatchSolver.solve(
        units: [unit1, unit2Capped],
        demand: 1100.0,
        enforceLimits: true,
      );

      expect(res.isFeasible, isTrue);
      expect(res.powers['u2']!, closeTo(500.0, 1e-5)); // Unit 2 clamped at 500 MW
      expect(res.powers['u1']!, closeTo(600.0, 1e-5)); // Unit 1 carries 1100 - 500 = 600 MW
      expect(res.clampedUnits.containsKey('u2'), isTrue);
      expect(res.steps.length, greaterThan(1));
    });

    test('Loss-included economic dispatch with Kron B-matrix', () {
      final bMatrix = [
        [0.0001, 0.00001],
        [0.00001, 0.00015],
      ];
      final lossCoeffs = LossCoefficients(bMatrix: bMatrix);

      final res = LossDispatchSolver.solve(
        units: [unit1, unit2],
        demand: 800.0,
        lossCoeffs: lossCoeffs,
        tolerance: 1e-4,
      );

      expect(res.converged, isTrue);
      expect(res.transmissionLoss, greaterThan(0.0));
      // Total generation must satisfy: sum(P_Gi) = P_D + P_L
      expect(res.totalPower, closeTo(800.0 + res.transmissionLoss, 1e-3));
      // Penalty factors L_i must be > 1 due to positive transmission losses
      expect(res.penaltyFactors['u1']!, greaterThan(1.0));
      expect(res.penaltyFactors['u2']!, greaterThan(1.0));
    });
  });
}
