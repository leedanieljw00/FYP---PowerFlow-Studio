import 'complex.dart';
import 'matrix.dart';

/// Per-unit parameters of a transmission line or transformer branch.
///
/// Bus indices are **0-based**. The branch is modelled as a nominal-π
/// section in series with an ideal `a : 1` transformer located at the
/// **from-bus** side (MATPOWER convention). A plain line has `tap = 1`.
class BranchParams {
  const BranchParams({
    required this.from,
    required this.to,
    required this.r,
    required this.x,
    this.bHalf = 0.0,
    this.tap = 1.0,
  });

  /// 0-based sending-end bus index.
  final int from;

  /// 0-based receiving-end bus index.
  final int to;

  /// Series resistance R (pu).
  final double r;

  /// Series reactance X (pu).
  final double x;

  /// Half line-charging susceptance B/2 (pu), applied at each end.
  final double bHalf;

  /// Off-nominal tap ratio `a` (dimensionless, > 0).
  final double tap;

  Complex get seriesImpedance => Complex(r, x);

  /// `y = 1 / (R + jX)`.
  Complex get seriesAdmittance => Complex.one / seriesImpedance;

  /// `j·B/2`.
  Complex get shuntHalf => Complex(0.0, bHalf);

  bool get isTransformer => tap != 1.0;
}

/// Two-port admittance parameters of a branch:
///
/// ```
/// ⎡I_f⎤   ⎡Y_ff  Y_ft⎤ ⎡V_f⎤
/// ⎣I_t⎦ = ⎣Y_tf  Y_tt⎦ ⎣V_t⎦
/// ```
class BranchAdmittance {
  const BranchAdmittance({
    required this.yff,
    required this.yft,
    required this.ytf,
    required this.ytt,
  });

  final Complex yff;
  final Complex yft;
  final Complex ytf;
  final Complex ytt;
}

/// Assembles the bus admittance matrix `Y_bus` from branch data.
///
/// For each branch with series admittance `y`, half charging `jB/2` and tap `a`:
///
/// * `Y_ff += (y + jB/2) / a²`
/// * `Y_tt += y + jB/2`
/// * `Y_ft = Y_tf −= y / a`
///
/// With `a = 1` this reduces to the textbook rules
/// `Y_ii = Σ (y_ik + jB_ik/2)` and `Y_ij = −y_ij`.
abstract final class YBusBuilder {
  /// Two-port admittances of a single branch.
  static BranchAdmittance branchAdmittance(BranchParams b) {
    if (b.r == 0.0 && b.x == 0.0) {
      throw ArgumentError('Branch series impedance cannot be zero.');
    }
    if (!(b.tap > 0.0)) {
      throw ArgumentError('Tap ratio must be positive (got ${b.tap}).');
    }
    final ys = b.seriesAdmittance;
    final ytt = ys + b.shuntHalf;
    final a = b.tap;
    final mutual = (-ys).scale(1.0 / a);
    return BranchAdmittance(
      yff: ytt.scale(1.0 / (a * a)),
      yft: mutual,
      ytf: mutual,
      ytt: ytt,
    );
  }

  /// Builds the `busCount × busCount` Y-bus.
  ///
  /// [busShunts] optionally adds fixed shunt admittances `y_sh,i` to the
  /// diagonal (e.g. capacitor banks), in per unit.
  static ComplexMatrix build(
    int busCount,
    List<BranchParams> branches, {
    List<Complex>? busShunts,
  }) {
    if (busCount < 1) {
      throw ArgumentError('Bus count must be at least 1.');
    }
    if (busShunts != null && busShunts.length != busCount) {
      throw ArgumentError('busShunts length must equal busCount.');
    }
    final y = ComplexMatrix(busCount, busCount);
    for (var k = 0; k < branches.length; k++) {
      final b = branches[k];
      final label = 'Line ${k + 1}';
      if (b.from < 0 || b.from >= busCount || b.to < 0 || b.to >= busCount) {
        throw ArgumentError('$label: bus index out of range.');
      }
      if (b.from == b.to) {
        throw ArgumentError('$label: from-bus and to-bus must differ.');
      }
      final BranchAdmittance adm;
      try {
        adm = branchAdmittance(b);
      } on ArgumentError catch (e) {
        throw ArgumentError('$label: ${e.message}');
      }
      y.addTo(b.from, b.from, adm.yff);
      y.addTo(b.to, b.to, adm.ytt);
      y.addTo(b.from, b.to, adm.yft);
      y.addTo(b.to, b.from, adm.ytf);
    }
    if (busShunts != null) {
      for (var i = 0; i < busCount; i++) {
        y.addTo(i, i, busShunts[i]);
      }
    }
    return y;
  }
}
