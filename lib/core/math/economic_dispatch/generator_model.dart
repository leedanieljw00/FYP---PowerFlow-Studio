/// Represents a thermal generating unit with a quadratic fuel cost curve:
/// C_i(P_i) = alpha_i + beta_i * P_i + gamma_i * P_i^2 ($/h)
///
/// Incremental Cost Rate (ICR):
/// dC_i/dP_i = beta_i + 2 * gamma_i * P_i ($/MWh)
class GeneratorUnit {
  const GeneratorUnit({
    required this.id,
    required this.name,
    required this.alpha,
    required this.beta,
    required this.gamma,
    required this.pMin,
    required this.pMax,
    this.isActive = true,
  }) : assert(pMin <= pMax, 'pMin cannot exceed pMax'),
       assert(gamma >= 0, 'gamma must be non-negative');

  final String id;
  final String name;

  /// Constant cost coefficient ($/h)
  final double alpha;

  /// Linear cost coefficient ($/MWh)
  final double beta;

  /// Quadratic cost coefficient ($/MW^2·h)
  final double gamma;

  /// Minimum power output (MW)
  final double pMin;

  /// Maximum power output (MW)
  final double pMax;

  /// Whether this unit is committed / on-line
  final bool isActive;

  /// Evaluates total generation cost ($/h) for output [p] (MW).
  double costAt(double p) {
    return alpha + beta * p + gamma * p * p;
  }

  /// Evaluates Incremental Cost Rate (ICR) or marginal cost ($/MWh) for output [p] (MW).
  double icrAt(double p) {
    return beta + 2.0 * gamma * p;
  }

  /// Calculates power output (MW) corresponding to a given incremental cost [lambda],
  /// ignoring limits.
  double powerAtLambda(double lambda) {
    if (gamma == 0) {
      return lambda >= beta ? pMax : pMin;
    }
    return (lambda - beta) / (2.0 * gamma);
  }

  GeneratorUnit copyWith({
    String? id,
    String? name,
    double? alpha,
    double? beta,
    double? gamma,
    double? pMin,
    double? pMax,
    bool? isActive,
  }) {
    return GeneratorUnit(
      id: id ?? this.id,
      name: name ?? this.name,
      alpha: alpha ?? this.alpha,
      beta: beta ?? this.beta,
      gamma: gamma ?? this.gamma,
      pMin: pMin ?? this.pMin,
      pMax: pMax ?? this.pMax,
      isActive: isActive ?? this.isActive,
    );
  }
}
