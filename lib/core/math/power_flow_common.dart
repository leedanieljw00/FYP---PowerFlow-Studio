import 'dart:math' as math;

import '../utils/format.dart';
import 'complex.dart';
import 'matrix.dart';
import 'ybus_builder.dart';

// ---------------------------------------------------------------------------
// Enumerations
// ---------------------------------------------------------------------------

/// Classification of a bus in the load-flow problem.
enum BusType { slack, pv, pq }

extension BusTypeInfo on BusType {
  String get label => switch (this) {
        BusType.slack => 'Slack',
        BusType.pv => 'PV',
        BusType.pq => 'PQ',
      };

  String get longLabel => switch (this) {
        BusType.slack => 'Slack / swing bus',
        BusType.pv => 'Generator (PV) bus',
        BusType.pq => 'Load (PQ) bus',
      };

  String get knownUnknown => switch (this) {
        BusType.slack => 'Specified: |V|, δ   ·   Solved: P, Q',
        BusType.pv => 'Specified: P, |V|   ·   Solved: Q, δ',
        BusType.pq => 'Specified: P, Q   ·   Solved: |V|, δ',
      };
}

/// Iterative algorithm used to solve the power-flow equations.
enum PowerFlowMethod { newtonRaphson, gaussSeidel }

extension PowerFlowMethodInfo on PowerFlowMethod {
  String get label => switch (this) {
        PowerFlowMethod.newtonRaphson => 'Newton–Raphson',
        PowerFlowMethod.gaussSeidel => 'Gauss–Seidel',
      };

  String get shortLabel => switch (this) {
        PowerFlowMethod.newtonRaphson => 'NR',
        PowerFlowMethod.gaussSeidel => 'GS',
      };
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// Solver-level description of a bus. **All quantities are per unit,
/// angles in radians.**
class PfBus {
  const PfBus({
    required this.type,
    this.vMag = 1.0,
    this.angle = 0.0,
    this.pGen = 0.0,
    this.qGen = 0.0,
    this.pLoad = 0.0,
    this.qLoad = 0.0,
    this.qMin,
    this.qMax,
  });

  final BusType type;

  /// Specified |V| (slack, PV) or initial guess (PQ).
  final double vMag;

  /// Specified δ (slack) or initial guess (PV, PQ), radians.
  final double angle;

  final double pGen;
  final double qGen;
  final double pLoad;
  final double qLoad;

  /// Generator reactive limits `Q_G,min` / `Q_G,max` (PV buses), or `null`.
  final double? qMin;
  final double? qMax;

  /// Scheduled real injection `P_sch = P_G − P_L`.
  double get pSpec => pGen - pLoad;

  /// Scheduled reactive injection `Q_sch = Q_G − Q_L`.
  double get qSpec => qGen - qLoad;
}

/// Tunable solver parameters.
class SolverOptions {
  const SolverOptions({
    this.tolerance = 1e-4,
    this.maxIterations = 50,
    this.enforceQLimits = true,
    this.accelerationFactor = 1.0,
    this.qLimitStartIteration = 1,
  });

  /// Convergence threshold ε (pu). NR: max |ΔP|,|ΔQ|. GS: max |ΔV|.
  final double tolerance;

  /// Maximum number of corrective iterations.
  final int maxIterations;

  /// Convert PV buses violating `Q_min/Q_max` into PQ buses at the limit.
  final bool enforceQLimits;

  /// Gauss–Seidel acceleration factor α (1.0 = none, typically 1.4–1.6).
  final double accelerationFactor;

  /// First iteration at which Q-limits are checked.
  final int qLimitStartIteration;

  void validate() {
    if (!(tolerance > 0)) {
      throw const PowerFlowException('Tolerance ε must be positive.');
    }
    if (maxIterations < 1) {
      throw const PowerFlowException('Max iterations must be at least 1.');
    }
    if (!(accelerationFactor > 0 && accelerationFactor < 2)) {
      throw const PowerFlowException(
        'Acceleration factor α must lie in (0, 2).',
      );
    }
  }
}

/// Raised for invalid power-flow input data.
class PowerFlowException implements Exception {
  const PowerFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

/// Complex power flowing on a branch, per unit.
class LineFlow {
  const LineFlow({
    required this.branchIndex,
    required this.from,
    required this.to,
    required this.sFromTo,
    required this.sToFrom,
    required this.iFrom,
    required this.iTo,
  });

  final int branchIndex;

  /// 0-based bus indices.
  final int from;
  final int to;

  /// `S_ij` measured at the sending end.
  final Complex sFromTo;

  /// `S_ji` measured at the receiving end.
  final Complex sToFrom;

  /// Current phasors entering the branch at each terminal.
  final Complex iFrom;
  final Complex iTo;

  /// `S_L,ij = S_ij + S_ji`.
  Complex get loss => sFromTo + sToFrom;
}

/// Snapshot of one iteration, shared by both solvers.
sealed class IterationRecord {
  const IterationRecord({
    required this.k,
    required this.vMag,
    required this.angle,
    required this.maxError,
    required this.busTypes,
    this.notes = const [],
  });

  /// Iteration counter (1-based).
  final int k;

  /// State **after** this iteration.
  final List<double> vMag;
  final List<double> angle;

  /// Convergence metric of this iteration (see [errorLabel]).
  final double maxError;

  /// Effective bus types used during this iteration.
  final List<BusType> busTypes;

  /// Human-readable events (Q-limit switching, divergence warnings…).
  final List<String> notes;

  String get errorLabel;
}

/// Newton–Raphson iteration: mismatch → Jacobian → correction.
final class NrIterationRecord extends IterationRecord {
  const NrIterationRecord({
    required super.k,
    required super.vMag,
    required super.angle,
    required super.maxError,
    required super.busTypes,
    super.notes,
    required this.angleBuses,
    required this.magBuses,
    required this.pScheduled,
    required this.pCalculated,
    required this.qScheduled,
    required this.qCalculated,
    required this.deltaP,
    required this.deltaQ,
    required this.jacobian,
    required this.dAngle,
    required this.dVmag,
  });

  /// Buses whose δ is unknown (all non-slack) — order of ΔP rows / Δδ cols.
  final List<int> angleBuses;

  /// Buses whose |V| is unknown (PQ) — order of ΔQ rows / Δ|V| cols.
  final List<int> magBuses;

  final List<double> pScheduled;
  final List<double> pCalculated;
  final List<double> qScheduled;
  final List<double> qCalculated;
  final List<double> deltaP;
  final List<double> deltaQ;

  /// Full Jacobian `[[J1, J2], [J3, J4]]`.
  final RealMatrix jacobian;

  /// Corrections Δδ (rad) and Δ|V| (pu).
  final List<double> dAngle;
  final List<double> dVmag;

  int get na => angleBuses.length;
  int get nm => magBuses.length;
  int get size => na + nm;

  /// ∂P/∂δ
  RealMatrix get j1 => jacobian.subMatrix(0, na, 0, na);

  /// ∂P/∂|V|
  RealMatrix get j2 => jacobian.subMatrix(0, na, na, size);

  /// ∂Q/∂δ
  RealMatrix get j3 => jacobian.subMatrix(na, size, 0, na);

  /// ∂Q/∂|V|
  RealMatrix get j4 => jacobian.subMatrix(na, size, na, size);

  @override
  String get errorLabel => 'max |ΔP|, |ΔQ|';
}

/// Gauss–Seidel sweep.
final class GsIterationRecord extends IterationRecord {
  const GsIterationRecord({
    required super.k,
    required super.vMag,
    required super.angle,
    required super.maxError,
    required super.busTypes,
    super.notes,
    required this.vBefore,
    required this.vAfter,
    required this.deltaV,
    required this.qInjection,
  });

  final List<Complex> vBefore;
  final List<Complex> vAfter;

  /// `|V_i^(k) − V_i^(k−1)|`.
  final List<double> deltaV;

  /// Reactive injection used for PV buses this sweep (computed or clamped).
  final Map<int, double> qInjection;

  @override
  String get errorLabel => 'max |ΔV|';
}

/// Final outcome of a power-flow solution (per unit, radians).
class PowerFlowResult {
  const PowerFlowResult({
    required this.method,
    required this.converged,
    required this.message,
    required this.ybus,
    required this.buses,
    required this.finalBusTypes,
    required this.voltages,
    required this.injections,
    required this.lineFlows,
    required this.iterations,
    required this.finalPowerMismatch,
    required this.options,
  });

  final PowerFlowMethod method;
  final bool converged;
  final String message;
  final ComplexMatrix ybus;
  final List<PfBus> buses;
  final List<BusType> finalBusTypes;
  final List<Complex> voltages;

  /// Net complex injection `S_i = V_i (Σ Y_ik V_k)*`.
  final List<Complex> injections;
  final List<LineFlow> lineFlows;
  final List<IterationRecord> iterations;

  /// Max |ΔP|,|ΔQ| at the final operating point.
  final double finalPowerMismatch;
  final SolverOptions options;

  int get iterationCount => iterations.length;

  List<double> get vMag => [for (final v in voltages) v.abs];

  List<double> get angle => [for (final v in voltages) v.arg];

  /// `P_G = P_i + P_L`.
  List<double> get pGen =>
      [for (var i = 0; i < buses.length; i++) injections[i].re + buses[i].pLoad];

  /// `Q_G = Q_i + Q_L`.
  List<double> get qGen =>
      [for (var i = 0; i < buses.length; i++) injections[i].im + buses[i].qLoad];

  Complex get totalLoss =>
      lineFlows.fold(Complex.zero, (acc, f) => acc + f.loss);

  Complex get totalGeneration {
    var s = Complex.zero;
    for (var i = 0; i < buses.length; i++) {
      s = s + Complex(pGen[i], qGen[i]);
    }
    return s;
  }

  Complex get totalLoad {
    var s = Complex.zero;
    for (final b in buses) {
      s = s + Complex(b.pLoad, b.qLoad);
    }
    return s;
  }
}

// ---------------------------------------------------------------------------
// Shared numerics
// ---------------------------------------------------------------------------

abstract final class PowerFlowMath {
  /// Checks structural validity common to every solver.
  static void validateSystem(ComplexMatrix ybus, List<PfBus> buses) {
    final n = buses.length;
    if (n < 2) {
      throw const PowerFlowException('At least two buses are required.');
    }
    if (ybus.rows != n || ybus.cols != n) {
      throw PowerFlowException(
        'Y-bus is ${ybus.rows}×${ybus.cols} but there are $n buses.',
      );
    }
    final slacks = buses.where((b) => b.type == BusType.slack).length;
    if (slacks != 1) {
      throw PowerFlowException(
        'Exactly one slack bus is required (found $slacks).',
      );
    }
    for (var i = 0; i < n; i++) {
      if (!(buses[i].vMag > 0)) {
        throw PowerFlowException('Bus ${i + 1}: |V| must be positive.');
      }
      if (ybus.get(i, i).isZero) {
        throw PowerFlowException(
          'Bus ${i + 1} is isolated (Y${sub(i + 1)}${sub(i + 1)} = 0).',
        );
      }
    }
  }

  /// Polar-form injections:
  /// `P_i = Σ |V_i||V_k||Y_ik| cos(θ_ik − δ_i + δ_k)`,
  /// `Q_i = −Σ |V_i||V_k||Y_ik| sin(θ_ik − δ_i + δ_k)`.
  static (List<double>, List<double>) polarInjections(
    List<double> vm,
    List<double> va,
    List<List<double>> yAbs,
    List<List<double>> yAng,
  ) {
    final n = vm.length;
    final p = List<double>.filled(n, 0.0);
    final q = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < n; k++) {
        final y = yAbs[i][k];
        if (y == 0) continue;
        final a = yAng[i][k] - va[i] + va[k];
        final m = vm[i] * vm[k] * y;
        p[i] += m * math.cos(a);
        q[i] -= m * math.sin(a);
      }
    }
    return (p, q);
  }

  /// `S_i = V_i · (Σ_k Y_ik V_k)*`.
  static List<Complex> injections(ComplexMatrix ybus, List<Complex> v) {
    final i = ybus.multiplyVector(v);
    return [for (var k = 0; k < v.length; k++) v[k] * i[k].conjugate];
  }

  /// Branch power flows using the same π/tap model as the Y-bus.
  static List<LineFlow> lineFlows(
    List<BranchParams> branches,
    List<Complex> v,
  ) {
    return [
      for (var k = 0; k < branches.length; k++)
        () {
          final b = branches[k];
          final adm = YBusBuilder.branchAdmittance(b);
          final vf = v[b.from];
          final vt = v[b.to];
          final iF = adm.yff * vf + adm.yft * vt;
          final iT = adm.ytf * vf + adm.ytt * vt;
          return LineFlow(
            branchIndex: k,
            from: b.from,
            to: b.to,
            sFromTo: vf * iF.conjugate,
            sToFrom: vt * iT.conjugate,
            iFrom: iF,
            iTo: iT,
          );
        }(),
    ];
  }

  /// Builds the result object shared by GS and NR.
  static PowerFlowResult assembleResult({
    required PowerFlowMethod method,
    required bool converged,
    required String message,
    required ComplexMatrix ybus,
    required List<PfBus> buses,
    required List<BranchParams> branches,
    required List<Complex> voltages,
    required List<BusType> finalTypes,
    required List<double> qSpecEffective,
    required List<IterationRecord> iterations,
    required SolverOptions options,
  }) {
    final allFinite = voltages.every((v) => v.isFinite);
    final s = allFinite
        ? injections(ybus, voltages)
        : List<Complex>.filled(voltages.length, const Complex(double.nan));
    final flows = allFinite ? lineFlows(branches, voltages) : <LineFlow>[];
    var mismatch = 0.0;
    for (var i = 0; i < buses.length; i++) {
      if (finalTypes[i] == BusType.slack) continue;
      mismatch = math.max(mismatch, (buses[i].pSpec - s[i].re).abs());
      if (finalTypes[i] == BusType.pq) {
        mismatch = math.max(mismatch, (qSpecEffective[i] - s[i].im).abs());
      }
    }
    if (!allFinite) mismatch = double.nan;
    return PowerFlowResult(
      method: method,
      converged: converged,
      message: message,
      ybus: ybus,
      buses: List.unmodifiable(buses),
      finalBusTypes: List.unmodifiable(finalTypes),
      voltages: List.unmodifiable(voltages),
      injections: List.unmodifiable(s),
      lineFlows: List.unmodifiable(flows),
      iterations: List.unmodifiable(iterations),
      finalPowerMismatch: mismatch,
      options: options,
    );
  }
}
