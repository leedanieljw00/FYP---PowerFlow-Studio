import 'lfc_models.dart';

/// Steady-state result for a two-area interconnected power system.
class TwoAreaLfcResult {
  const TwoAreaLfcResult({
    required this.deltaPL1_MW,
    required this.deltaPL2_MW,
    required this.beta1,
    required this.beta2,
    required this.b1,
    required this.b2,
    required this.deltaF_pu,
    required this.deltaF_Hz,
    required this.fFinal_Hz,
    required this.deltaPtie1_pu,
    required this.deltaPtie1_MW,
    required this.deltaPtie2_pu,
    required this.deltaPtie2_MW,
    required this.ace1_pu,
    required this.ace1_MW,
    required this.ace2_pu,
    required this.ace2_MW,
    required this.deltaPm1_MW,
    required this.deltaPm2_MW,
  });

  final double deltaPL1_MW;
  final double deltaPL2_MW;
  final double beta1;
  final double beta2;
  final double b1;
  final double b2;

  final double deltaF_pu;
  final double deltaF_Hz;
  final double fFinal_Hz;

  /// Tie-line power deviation from Area 1 to Area 2 (pu on system base)
  final double deltaPtie1_pu;

  /// Tie-line power deviation in MW
  final double deltaPtie1_MW;

  /// Tie-line power deviation from Area 2 to Area 1 (deltaPtie2 = -deltaPtie1)
  final double deltaPtie2_pu;
  final double deltaPtie2_MW;

  /// Area Control Error for Area 1 (ACE_1 = ΔP_tie1 + B_1 * Δf)
  final double ace1_pu;
  final double ace1_MW;

  /// Area Control Error for Area 2 (ACE_2 = ΔP_tie2 + B_2 * Δf)
  final double ace2_pu;
  final double ace2_MW;

  /// Total governor response in Area 1 (MW)
  final double deltaPm1_MW;

  /// Total governor response in Area 2 (MW)
  final double deltaPm2_MW;
}

abstract final class TwoAreaLfcSolver {
  /// Solves two-area interconnected frequency deviation, tie-line flow, and ACEs.
  ///
  /// [deltaPL1_MW] is the load step in Area 1 (MW).
  /// [deltaPL2_MW] is the load step in Area 2 (MW).
  static TwoAreaLfcResult solve({
    required LfcArea area1,
    required LfcArea area2,
    required double deltaPL1_MW,
    required double deltaPL2_MW,
    double? customB1,
    double? customB2,
  }) {
    // Both areas evaluated on area1's system base or common base
    final sBase = area1.systemMvaBase;
    final f0 = area1.nominalFreq;

    final pl1_pu = deltaPL1_MW / sBase;
    final pl2_pu = deltaPL2_MW / sBase;

    final beta1 = area1.betaSys;
    final beta2 = area2.betaSys;

    final b1 = customB1 ?? area1.effectiveB;
    final b2 = customB2 ?? area2.effectiveB;

    // Steady-state frequency deviation for interconnected grid:
    // delta_f = - (delta_P_L1 + delta_P_L2) / (beta_1 + beta_2)
    final sumBeta = beta1 + beta2;
    final deltaF_pu = sumBeta > 0 ? -(pl1_pu + pl2_pu) / sumBeta : 0.0;
    final deltaF_Hz = deltaF_pu * f0;
    final fFinal_Hz = f0 + deltaF_Hz;

    // Tie-line power flow from Area 1 to Area 2:
    // delta_P_tie1 = (delta_P_L2 * beta_1 - delta_P_L1 * beta_2) / (beta_1 + beta_2)
    final deltaPtie1_pu = sumBeta > 0 ? (pl2_pu * beta1 - pl1_pu * beta2) / sumBeta : 0.0;
    final deltaPtie2_pu = -deltaPtie1_pu;

    final deltaPtie1_MW = deltaPtie1_pu * sBase;
    final deltaPtie2_MW = deltaPtie2_pu * sBase;

    // Area Control Error (ACE):
    // ACE_1 = delta_P_tie1 + B_1 * delta_f
    // ACE_2 = delta_P_tie2 + B_2 * delta_f
    final ace1_pu = deltaPtie1_pu + b1 * deltaF_pu;
    final ace2_pu = deltaPtie2_pu + b2 * deltaF_pu;

    // Generator outputs in Area 1 and Area 2
    final gov1_pu = -deltaF_pu * (beta1 - area1.dampingD);
    final gov2_pu = -deltaF_pu * (beta2 - area2.dampingD);

    return TwoAreaLfcResult(
      deltaPL1_MW: deltaPL1_MW,
      deltaPL2_MW: deltaPL2_MW,
      beta1: beta1,
      beta2: beta2,
      b1: b1,
      b2: b2,
      deltaF_pu: deltaF_pu,
      deltaF_Hz: deltaF_Hz,
      fFinal_Hz: fFinal_Hz,
      deltaPtie1_pu: deltaPtie1_pu,
      deltaPtie1_MW: deltaPtie1_MW,
      deltaPtie2_pu: deltaPtie2_pu,
      deltaPtie2_MW: deltaPtie2_MW,
      ace1_pu: ace1_pu,
      ace1_MW: ace1_pu * sBase,
      ace2_pu: ace2_pu,
      ace2_MW: ace2_pu * sBase,
      deltaPm1_MW: gov1_pu * sBase,
      deltaPm2_MW: gov2_pu * sBase,
    );
  }

  /// Inverts ACE measurements to calculate tie-line flow and frequency deviation.
  /// Used in EE4530 Assignment 1 Q1:
  /// ACE_1 = ΔP_tie1 + B_1 * Δf
  /// ACE_2 = -ΔP_tie1 + B_2 * Δf
  /// => Δf = (ACE_1 + ACE_2) / (B_1 + B_2)
  /// => ΔP_tie1 = (B_2 * ACE_1 - B_1 * ACE_2) / (B_1 + B_2)
  static ({double deltaF_pu, double deltaPtie1_pu}) solveFromAces({
    required double ace1,
    required double ace2,
    required double b1,
    required double b2,
  }) {
    final sumB = b1 + b2;
    if (sumB == 0) return (deltaF_pu: 0.0, deltaPtie1_pu: 0.0);
    final df = (ace1 + ace2) / sumB;
    final dPtie1 = (b2 * ace1 - b1 * ace2) / sumB;
    return (deltaF_pu: df, deltaPtie1_pu: dPtie1);
  }
}
