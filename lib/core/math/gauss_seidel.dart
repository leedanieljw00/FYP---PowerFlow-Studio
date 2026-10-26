import '../utils/format.dart';
import 'complex.dart';
import 'matrix.dart';
import 'power_flow_common.dart';
import 'ybus_builder.dart';

export 'power_flow_common.dart';

/// Gauss–Seidel load-flow solver.
///
/// For every non-slack bus, in order, using the most recent voltages:
///
/// ```
/// V_i ← (1/Y_ii)·[ (P_i − jQ_i)/V_i* − Σ_{k≠i} Y_ik V_k ]
/// ```
///
/// PV buses first compute `Q_i = −Im{V_i* Σ_k Y_ik V_k}`; if the resulting
/// `Q_G` violates a limit it is clamped and the bus is treated as PQ for
/// that sweep, otherwise the magnitude is reset to `|V_spec|`.
/// Convergence: `max_i |V_i^(k) − V_i^(k−1)| < ε`.
class GaussSeidelSolver {
  const GaussSeidelSolver({
    this.options = const SolverOptions(maxIterations: 200),
  });

  final SolverOptions options;

  PowerFlowResult solve({
    required ComplexMatrix ybus,
    required List<PfBus> buses,
    List<BranchParams> branches = const [],
  }) {
    options.validate();
    PowerFlowMath.validateSystem(ybus, buses);

    final n = buses.length;
    final v = [for (final b in buses) Complex.polar(b.vMag, b.angle)];
    final qSpec = [for (final b in buses) b.qSpec];
    var types = [for (final b in buses) b.type];
    final alpha = options.accelerationFactor;

    final records = <IterationRecord>[];
    var converged = false;
    var message = '';

    for (var k = 1; k <= options.maxIterations; k++) {
      final vBefore = List<Complex>.of(v);
      final effTypes = [for (final b in buses) b.type];
      final qUsed = <int, double>{};
      final notes = <String>[];

      for (var i = 0; i < n; i++) {
        final b = buses[i];
        if (b.type == BusType.slack) continue;

        var sum = Complex.zero; // Σ_{m≠i} Y_im V_m (latest values)
        for (var m = 0; m < n; m++) {
          if (m == i) continue;
          final y = ybus.get(i, m);
          if (y.isZero) continue;
          sum = sum + y * v[m];
        }
        final yii = ybus.get(i, i);

        var qi = b.qSpec;
        var holdMagnitude = false;
        if (b.type == BusType.pv) {
          final qCalc = -(v[i].conjugate * (sum + yii * v[i])).im;
          qi = qCalc;
          holdMagnitude = true;
          if (options.enforceQLimits && k >= options.qLimitStartIteration) {
            final qg = qCalc + b.qLoad;
            final qMax = b.qMax;
            final qMin = b.qMin;
            if (qMax != null && qg > qMax) {
              qi = qMax - b.qLoad;
              holdMagnitude = false;
              effTypes[i] = BusType.pq;
              notes.add('Bus ${i + 1}: Q_G = ${fmtNum(qg)} pu > Q_max = '
                  '${fmtNum(qMax)} pu → clamped, treated as PQ this sweep.');
            } else if (qMin != null && qg < qMin) {
              qi = qMin - b.qLoad;
              holdMagnitude = false;
              effTypes[i] = BusType.pq;
              notes.add('Bus ${i + 1}: Q_G = ${fmtNum(qg)} pu < Q_min = '
                  '${fmtNum(qMin)} pu → clamped, treated as PQ this sweep.');
            }
          }
          qUsed[i] = qi;
        }

        var vNew = (Complex(b.pSpec, -qi) / v[i].conjugate - sum) / yii;
        if (holdMagnitude) {
          vNew = Complex.polar(b.vMag, vNew.arg);
        } else if (alpha != 1.0) {
          vNew = v[i] + (vNew - v[i]).scale(alpha);
        }
        v[i] = vNew;
        qSpec[i] = qi;
      }

      final dV = [for (var i = 0; i < n; i++) (v[i] - vBefore[i]).abs];
      final maxDv = maxAbsOf(dV);
      types = effTypes;

      records.add(GsIterationRecord(
        k: k,
        vMag: List.unmodifiable([for (final x in v) x.abs]),
        angle: List.unmodifiable([for (final x in v) x.arg]),
        maxError: maxDv,
        busTypes: List.unmodifiable(effTypes),
        notes: List.unmodifiable(notes),
        vBefore: List.unmodifiable(vBefore),
        vAfter: List.unmodifiable(v),
        deltaV: List.unmodifiable(dV),
        qInjection: Map.unmodifiable(qUsed),
      ));

      if (!maxDv.isFinite || v.any((x) => !x.isFinite)) {
        message = 'Solution diverged at iteration $k.';
        break;
      }
      if (maxDv < options.tolerance) {
        converged = true;
        message = 'Converged after $k iteration(s): max |ΔV| = '
            '${fmtSci(maxDv)} < ε = ${fmtSci(options.tolerance, 1)} pu.';
        break;
      }
    }
    if (!converged && message.isEmpty) {
      message = 'Did not converge within ${options.maxIterations} iterations '
          '(last max |ΔV| = ${fmtSci(records.isEmpty ? double.nan : records.last.maxError)} pu).';
    }

    return PowerFlowMath.assembleResult(
      method: PowerFlowMethod.gaussSeidel,
      converged: converged,
      message: message,
      ybus: ybus,
      buses: buses,
      branches: branches,
      voltages: v,
      finalTypes: types,
      qSpecEffective: qSpec,
      iterations: records,
      options: options,
    );
  }
}
