import '../models/dynamic_lfc_params.dart';

/// High-precision numerical simulation engine for closed-loop turbine-governor frequency dynamics.
abstract final class LfcTransientEngine {
  /// Solves the differential state equations using 4th-order Runge-Kutta (RK4) integration:
  ///
  /// d(Δf)/dt    = (1 / 2H) * (ΔP_m - ΔP_L - D * Δf)
  /// d(ΔP_m)/dt  = (1 / τ_T) * (ΔP_v - ΔP_m)
  /// d(ΔP_v)/dt  = (1 / τ_g) * (ΔP_ref - (Δf / R) - ΔP_v)
  /// d(ΔP_ref)/dt = -K_I * Δf  (if enableAGC == true)
  static List<DynamicLfcTrajectoryPoint> simulate({
    required DynamicLfcParams params,
    required bool enableAGC,
  }) {
    final h = params.inertiaH;
    final d = params.dampingD;
    final r = params.droopR;
    final tauG = params.governorTau;
    final tauT = params.turbineTau;
    final ki = enableAGC ? params.integralGainKi : 0.0;
    final deltaPL_pu = params.deltaPL_pu;
    final sBase = params.systemMvaBase;
    final f0 = params.nominalFreq;
    final dt = params.dt;
    final tMax = params.tMax;

    // State vector: x = [Δf (pu), ΔP_m (pu), ΔP_v (pu), ΔP_ref (pu)]
    var x = [0.0, 0.0, 0.0, 0.0];

    List<double> evaluateDerivatives(List<double> s) {
      final df = s[0];
      final pm = s[1];
      final pv = s[2];
      final pref = s[3];

      final d_df = (pm - deltaPL_pu - d * df) / (2.0 * h);
      final d_pm = (pv - pm) / tauT;
      final d_pv = (pref - (df / r) - pv) / tauG;
      // Secondary Integral Action: d(ΔP_ref)/dt = -K_I * ACE = -K_I * (B * Δf)
      final ace = params.beta * df;
      final d_pref = -ki * ace;

      return [d_df, d_pm, d_pv, d_pref];
    }

    final trajectory = <DynamicLfcTrajectoryPoint>[];
    double t = 0.0;

    while (t <= tMax + 1e-5) {
      final df_pu = x[0];
      final df_Hz = df_pu * f0;
      final f_Hz = f0 + df_Hz;

      trajectory.add(DynamicLfcTrajectoryPoint(
        time: t,
        deltaF_pu: df_pu,
        deltaF_Hz: df_Hz,
        frequency_Hz: f_Hz,
        deltaPm_MW: x[1] * sBase,
        deltaPv_MW: x[2] * sBase,
        deltaPref_MW: x[3] * sBase,
      ));

      // 4th-Order Runge-Kutta (RK4) Step
      final k1 = evaluateDerivatives(x);

      final x2 = [for (var i = 0; i < 4; i++) x[i] + 0.5 * dt * k1[i]];
      final k2 = evaluateDerivatives(x2);

      final x3 = [for (var i = 0; i < 4; i++) x[i] + 0.5 * dt * k2[i]];
      final k3 = evaluateDerivatives(x3);

      final x4 = [for (var i = 0; i < 4; i++) x[i] + dt * k3[i]];
      final k4 = evaluateDerivatives(x4);

      for (var i = 0; i < 4; i++) {
        x[i] += (dt / 6.0) * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]);
      }

      t += dt;
    }

    return trajectory;
  }
}
