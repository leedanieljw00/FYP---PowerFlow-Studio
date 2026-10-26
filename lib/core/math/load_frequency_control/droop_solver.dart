import 'lfc_models.dart';

/// Individual generator steady-state response to frequency deviation.
class GeneratorDroopResponse {
  const GeneratorDroopResponse({
    required this.generatorId,
    required this.generatorName,
    required this.deltaP_pu,
    required this.deltaP_MW,
    required this.participationFactor,
  });

  final String generatorId;
  final String generatorName;

  /// Power deviation on system MVA base (pu)
  final double deltaP_pu;

  /// Power deviation in MW
  final double deltaP_MW;

  /// Fraction of total governor response supplied by this unit
  final double participationFactor;
}

/// Steady-state result of single-area static droop regulation.
class SingleAreaDroopResult {
  const SingleAreaDroopResult({
    required this.deltaPL_pu,
    required this.deltaPL_MW,
    required this.betaSys,
    required this.deltaF_pu,
    required this.deltaF_Hz,
    required this.fFinal_Hz,
    required this.generatorResponses,
    required this.dampingRelief_pu,
    required this.dampingRelief_MW,
    required this.totalGovernorPower_pu,
    required this.totalGovernorPower_MW,
  });

  final double deltaPL_pu;
  final double deltaPL_MW;
  final double betaSys;
  final double deltaF_pu;
  final double deltaF_Hz;
  final double fFinal_Hz;
  final List<GeneratorDroopResponse> generatorResponses;
  final double dampingRelief_pu;
  final double dampingRelief_MW;
  final double totalGovernorPower_pu;
  final double totalGovernorPower_MW;
}

/// Dynamic simulation time-step point.
class LfcSimulationPoint {
  const LfcSimulationPoint({
    required this.time,
    required this.deltaF_pu,
    required this.deltaF_Hz,
    required this.frequency_Hz,
    required this.deltaPm_pu,
    required this.deltaPv_pu,
    required this.deltaPref_pu,
  });

  final double time;
  final double deltaF_pu;
  final double deltaF_Hz;
  final double frequency_Hz;
  final double deltaPm_pu;
  final double deltaPv_pu;
  final double deltaPref_pu;
}

abstract final class DroopSolver {
  /// Solves static frequency deviation and generator load sharing.
  ///
  /// [deltaPL_MW] is the step increase in active load (MW).
  static SingleAreaDroopResult solveSteadyState({
    required LfcArea area,
    required double deltaPL_MW,
  }) {
    final sBase = area.systemMvaBase;
    final deltaPL_pu = deltaPL_MW / sBase;
    final beta = area.betaSys;

    // Steady-state frequency deviation: delta_f = - delta_P_L / beta_sys
    final deltaF_pu = beta > 0 ? -deltaPL_pu / beta : 0.0;
    final deltaF_Hz = deltaF_pu * area.nominalFreq;
    final fFinal = area.nominalFreq + deltaF_Hz;

    // Damping power relief: delta_P_D = D * delta_f (negative for load relief)
    final dampingRelief_pu = -area.dampingD * deltaF_pu;
    final dampingRelief_MW = dampingRelief_pu * sBase;

    // Generator responses: delta_P_mi = - delta_f / R_i,sys
    final responses = <GeneratorDroopResponse>[];
    double totalGov_pu = 0.0;

    for (final g in area.generators) {
      if (!g.isActive) continue;
      final rSys = g.droopOnSystemBase(sBase);
      final dp_pu = -deltaF_pu / rSys;
      totalGov_pu += dp_pu;
      responses.add(GeneratorDroopResponse(
        generatorId: g.id,
        generatorName: g.name,
        deltaP_pu: dp_pu,
        deltaP_MW: dp_pu * sBase,
        participationFactor: 0.0, // populated below
      ));
    }

    // Assign participation factors
    final normalizedResponses = responses.map((r) {
      final pf = totalGov_pu.abs() > 1e-12 ? r.deltaP_pu / totalGov_pu : 0.0;
      return GeneratorDroopResponse(
        generatorId: r.generatorId,
        generatorName: r.generatorName,
        deltaP_pu: r.deltaP_pu,
        deltaP_MW: r.deltaP_MW,
        participationFactor: pf,
      );
    }).toList();

    return SingleAreaDroopResult(
      deltaPL_pu: deltaPL_pu,
      deltaPL_MW: deltaPL_MW,
      betaSys: beta,
      deltaF_pu: deltaF_pu,
      deltaF_Hz: deltaF_Hz,
      fFinal_Hz: fFinal,
      generatorResponses: normalizedResponses,
      dampingRelief_pu: dampingRelief_pu,
      dampingRelief_MW: dampingRelief_MW,
      totalGovernorPower_pu: totalGov_pu,
      totalGovernorPower_MW: totalGov_pu * sBase,
    );
  }

  /// Simulates closed-loop dynamic frequency response over time using 4th-order Runge-Kutta.
  ///
  /// Solves the differential state equations:
  /// d(Δω)/dt   = (1 / 2H) * (ΔP_m - ΔP_L - D * Δω)
  /// d(ΔP_m)/dt = (1 / τ_T) * (ΔP_v - ΔP_m)
  /// d(ΔP_v)/dt = (1 / τ_g) * (ΔP_ref - (1/R_eq)*Δω - ΔP_v)
  /// d(ΔP_ref)/dt = -K_I * Δω  (if enableAGC)
  static List<LfcSimulationPoint> simulateTransient({
    required LfcArea area,
    required double deltaPL_MW,
    bool enableAGC = false,
    double tMax = 20.0,
    double dt = 0.01,
  }) {
    final sBase = area.systemMvaBase;
    final deltaPL_pu = deltaPL_MW / sBase;
    final f0 = area.nominalFreq;

    // Aggregate equivalent parameters
    final h = area.equivalentH;
    final d = area.dampingD;

    // Equivalent governor gain: 1 / R_eq = sum(1 / R_i,sys)
    double invReq = 0.0;
    double tauG_weighted = 0.0;
    double tauT_weighted = 0.0;
    int activeCount = 0;

    for (final g in area.generators) {
      if (g.isActive) {
        final gain = g.governorGainOnSystemBase(sBase);
        invReq += gain;
        tauG_weighted += g.governorTau;
        tauT_weighted += g.turbineTau;
        activeCount++;
      }
    }

    final tauG = activeCount > 0 ? tauG_weighted / activeCount : 0.08;
    final tauT = activeCount > 0 ? tauT_weighted / activeCount : 0.30;
    final ki = enableAGC ? area.integralGainKi : 0.0;

    // State vector: x = [Δω, ΔP_m, ΔP_v, ΔP_ref]
    var x = [0.0, 0.0, 0.0, 0.0];

    List<double> derivatives(List<double> s) {
      final w = s[0];
      final pm = s[1];
      final pv = s[2];
      final pref = s[3];

      final dw = (pm - deltaPL_pu - d * w) / (2.0 * h);
      final dpm = (pv - pm) / tauT;
      final dpv = (pref - invReq * w - pv) / tauG;
      final dpref = -ki * w;

      return [dw, dpm, dpv, dpref];
    }

    final trajectory = <LfcSimulationPoint>[];
    double t = 0.0;

    while (t <= tMax + 1e-6) {
      final df_Hz = x[0] * f0;
      trajectory.add(LfcSimulationPoint(
        time: t,
        deltaF_pu: x[0],
        deltaF_Hz: df_Hz,
        frequency_Hz: f0 + df_Hz,
        deltaPm_pu: x[1],
        deltaPv_pu: x[2],
        deltaPref_pu: x[3],
      ));

      // RK4 step
      final k1 = derivatives(x);
      final x2 = [for (var i = 0; i < 4; i++) x[i] + 0.5 * dt * k1[i]];
      final k2 = derivatives(x2);
      final x3 = [for (var i = 0; i < 4; i++) x[i] + 0.5 * dt * k2[i]];
      final k3 = derivatives(x3);
      final x4 = [for (var i = 0; i < 4; i++) x[i] + dt * k3[i]];
      final k4 = derivatives(x4);

      for (var i = 0; i < 4; i++) {
        x[i] += (dt / 6.0) * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]);
      }

      t += dt;
    }

    return trajectory;
  }
}
