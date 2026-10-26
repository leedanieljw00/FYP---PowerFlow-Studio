import 'dart:math' as math;

import '../utils/format.dart';
import 'complex.dart';
import 'matrix.dart';
import 'power_flow_common.dart';
import 'ybus_builder.dart';

export 'power_flow_common.dart';

/// Polar-form Newton–Raphson load-flow solver.
///
/// Unknowns: `δ_i` for every non-slack bus and `|V_i|` for every PQ bus.
/// Each iteration solves
///
/// ```
/// ⎡ΔP⎤   ⎡J1  J2⎤ ⎡ Δδ ⎤
/// ⎣ΔQ⎦ = ⎣J3  J4⎦ ⎣Δ|V|⎦
/// ```
///
/// with `J1 = ∂P/∂δ`, `J2 = ∂P/∂|V|`, `J3 = ∂Q/∂δ`, `J4 = ∂Q/∂|V|`.
/// Iteration stops when `max(|ΔP|, |ΔQ|) < ε`.
class NewtonRaphsonSolver {
  const NewtonRaphsonSolver({
    this.options = const SolverOptions(maxIterations: 20),
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
    final types = [for (final b in buses) b.type];
    final vm = [for (final b in buses) b.vMag];
    final va = [for (final b in buses) b.angle];
    final pSpec = [for (final b in buses) b.pSpec];
    final qSpec = [for (final b in buses) b.qSpec];
    final yAbs = [
      for (var i = 0; i < n; i++)
        [for (var k = 0; k < n; k++) ybus.get(i, k).abs],
    ];
    final yAng = [
      for (var i = 0; i < n; i++)
        [for (var k = 0; k < n; k++) ybus.get(i, k).arg],
    ];

    final records = <IterationRecord>[];
    var converged = false;
    var message = '';

    while (true) {
      // 1. Mismatch at the current state.
      final (p, q) = PowerFlowMath.polarInjections(vm, va, yAbs, yAng);
      final angleBuses = <int>[
        for (var i = 0; i < n; i++)
          if (types[i] != BusType.slack) i,
      ];
      final magBuses = <int>[
        for (var i = 0; i < n; i++)
          if (types[i] == BusType.pq) i,
      ];
      final pSched = [for (final i in angleBuses) pSpec[i]];
      final pCalc = [for (final i in angleBuses) p[i]];
      final qSched = [for (final i in magBuses) qSpec[i]];
      final qCalc = [for (final i in magBuses) q[i]];
      final dP = [for (var m = 0; m < pSched.length; m++) pSched[m] - pCalc[m]];
      final dQ = [for (var m = 0; m < qSched.length; m++) qSched[m] - qCalc[m]];
      final maxMismatch = maxAbsOf([...dP, ...dQ]);

      if (!maxMismatch.isFinite) {
        message = 'Solution diverged: mismatch became non-finite.';
        break;
      }
      if (maxMismatch < options.tolerance) {
        converged = true;
        message = 'Converged after ${records.length} iteration(s): '
            'max |ΔP|,|ΔQ| = ${fmtSci(maxMismatch)} < ε = '
            '${fmtSci(options.tolerance, 1)} pu.';
        break;
      }
      if (records.length >= options.maxIterations) {
        message = 'Did not converge within ${options.maxIterations} '
            'iterations (max mismatch ${fmtSci(maxMismatch)} pu).';
        break;
      }

      final k = records.length + 1;

      // 2. Jacobian and linear solve.
      final jac = buildJacobian(
        angleBuses: angleBuses,
        magBuses: magBuses,
        vm: vm,
        va: va,
        yAbs: yAbs,
        yAng: yAng,
      );
      final dx = _trySolve(jac, [...dP, ...dQ]);
      if (dx == null) {
        message = 'Jacobian is singular at iteration $k — '
            'check network connectivity and bus data.';
        break;
      }
      final na = angleBuses.length;
      final dDelta = dx.sublist(0, na);
      final dV = dx.sublist(na);
      final typesUsed = List<BusType>.of(types);

      // 3. State update.
      for (var m = 0; m < na; m++) {
        va[angleBuses[m]] += dDelta[m];
      }
      for (var m = 0; m < magBuses.length; m++) {
        vm[magBuses[m]] += dV[m];
      }

      final notes = <String>[];
      final physical = vm.every((v) => v.isFinite && v > 0) &&
          va.every((a) => a.isFinite);
      if (!physical) {
        notes.add('Update produced a non-physical state (|V| ≤ 0 or '
            'non-finite); iteration aborted.');
      } else if (options.enforceQLimits && k >= options.qLimitStartIteration) {
        // 4. Generator Q-limit enforcement (PV → PQ switching).
        final (_, qNew) = PowerFlowMath.polarInjections(vm, va, yAbs, yAng);
        for (var i = 0; i < n; i++) {
          if (types[i] != BusType.pv) continue;
          final b = buses[i];
          final qg = qNew[i] + b.qLoad;
          final qMax = b.qMax;
          final qMin = b.qMin;
          if (qMax != null && qg > qMax) {
            types[i] = BusType.pq;
            qSpec[i] = qMax - b.qLoad;
            notes.add('Bus ${i + 1}: Q_G = ${fmtNum(qg)} pu > Q_max = '
                '${fmtNum(qMax)} pu → switched PV→PQ with Q_G fixed at Q_max.');
          } else if (qMin != null && qg < qMin) {
            types[i] = BusType.pq;
            qSpec[i] = qMin - b.qLoad;
            notes.add('Bus ${i + 1}: Q_G = ${fmtNum(qg)} pu < Q_min = '
                '${fmtNum(qMin)} pu → switched PV→PQ with Q_G fixed at Q_min.');
          }
        }
      }

      records.add(NrIterationRecord(
        k: k,
        vMag: List.unmodifiable(vm),
        angle: List.unmodifiable(va),
        maxError: maxMismatch,
        busTypes: List.unmodifiable(typesUsed),
        notes: List.unmodifiable(notes),
        angleBuses: List.unmodifiable(angleBuses),
        magBuses: List.unmodifiable(magBuses),
        pScheduled: List.unmodifiable(pSched),
        pCalculated: List.unmodifiable(pCalc),
        qScheduled: List.unmodifiable(qSched),
        qCalculated: List.unmodifiable(qCalc),
        deltaP: List.unmodifiable(dP),
        deltaQ: List.unmodifiable(dQ),
        jacobian: jac,
        dAngle: List.unmodifiable(dDelta),
        dVmag: List.unmodifiable(dV),
      ));

      if (!physical) {
        message = 'Solution diverged at iteration $k.';
        break;
      }
    }

    return PowerFlowMath.assembleResult(
      method: PowerFlowMethod.newtonRaphson,
      converged: converged,
      message: message,
      ybus: ybus,
      buses: buses,
      branches: branches,
      voltages: [for (var i = 0; i < n; i++) Complex.polar(vm[i], va[i])],
      finalTypes: types,
      qSpecEffective: qSpec,
      iterations: records,
      options: options,
    );
  }

  /// Analytical polar Jacobian. Rows: `[ΔP(angleBuses), ΔQ(magBuses)]`,
  /// columns: `[δ(angleBuses), |V|(magBuses)]`.
  ///
  /// With `α_ik = θ_ik − δ_i + δ_k`:
  ///
  /// * J1: `∂P_i/∂δ_i = Σ_{k≠i} |V_i||V_k||Y_ik| sin α_ik`,
  ///       `∂P_i/∂δ_k = −|V_i||V_k||Y_ik| sin α_ik`
  /// * J2: `∂P_i/∂|V_i| = 2|V_i||Y_ii|cos θ_ii + Σ_{k≠i}|V_k||Y_ik| cos α_ik`,
  ///       `∂P_i/∂|V_k| = |V_i||Y_ik| cos α_ik`
  /// * J3: `∂Q_i/∂δ_i = Σ_{k≠i} |V_i||V_k||Y_ik| cos α_ik`,
  ///       `∂Q_i/∂δ_k = −|V_i||V_k||Y_ik| cos α_ik`
  /// * J4: `∂Q_i/∂|V_i| = −2|V_i||Y_ii| sin θ_ii − Σ_{k≠i}|V_k||Y_ik| sin α_ik`,
  ///       `∂Q_i/∂|V_k| = −|V_i||Y_ik| sin α_ik`
  static RealMatrix buildJacobian({
    required List<int> angleBuses,
    required List<int> magBuses,
    required List<double> vm,
    required List<double> va,
    required List<List<double>> yAbs,
    required List<List<double>> yAng,
  }) {
    final n = vm.length;
    final na = angleBuses.length;
    final nm = magBuses.length;
    final jac = RealMatrix(na + nm, na + nm);

    double alpha(int i, int k) => yAng[i][k] - va[i] + va[k];

    // Diagonal helper sums over k ≠ i.
    final sumSinPV = List<double>.filled(n, 0.0); // Σ |Vi||Vk||Yik| sin α
    final sumCosPV = List<double>.filled(n, 0.0); // Σ |Vi||Vk||Yik| cos α
    final sumCosV = List<double>.filled(n, 0.0); // Σ |Vk||Yik| cos α
    final sumSinV = List<double>.filled(n, 0.0); // Σ |Vk||Yik| sin α
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < n; k++) {
        if (k == i || yAbs[i][k] == 0) continue;
        final a = alpha(i, k);
        final s = math.sin(a);
        final c = math.cos(a);
        final vy = vm[k] * yAbs[i][k];
        sumSinPV[i] += vm[i] * vy * s;
        sumCosPV[i] += vm[i] * vy * c;
        sumCosV[i] += vy * c;
        sumSinV[i] += vy * s;
      }
    }

    // ΔP rows → J1 | J2
    for (var r = 0; r < na; r++) {
      final i = angleBuses[r];
      for (var c = 0; c < na; c++) {
        final k = angleBuses[c];
        jac[r][c] = i == k
            ? sumSinPV[i]
            : -vm[i] * vm[k] * yAbs[i][k] * math.sin(alpha(i, k));
      }
      for (var c = 0; c < nm; c++) {
        final k = magBuses[c];
        jac[r][na + c] = i == k
            ? 2 * vm[i] * yAbs[i][i] * math.cos(yAng[i][i]) + sumCosV[i]
            : vm[i] * yAbs[i][k] * math.cos(alpha(i, k));
      }
    }

    // ΔQ rows → J3 | J4
    for (var r = 0; r < nm; r++) {
      final i = magBuses[r];
      for (var c = 0; c < na; c++) {
        final k = angleBuses[c];
        jac[na + r][c] = i == k
            ? sumCosPV[i]
            : -vm[i] * vm[k] * yAbs[i][k] * math.cos(alpha(i, k));
      }
      for (var c = 0; c < nm; c++) {
        final k = magBuses[c];
        jac[na + r][na + c] = i == k
            ? -2 * vm[i] * yAbs[i][i] * math.sin(yAng[i][i]) - sumSinV[i]
            : -vm[i] * yAbs[i][k] * math.sin(alpha(i, k));
      }
    }
    return jac;
  }

  static List<double>? _trySolve(RealMatrix a, List<double> b) {
    try {
      return a.solve(b);
    } on SingularMatrixException {
      return null;
    }
  }
}
