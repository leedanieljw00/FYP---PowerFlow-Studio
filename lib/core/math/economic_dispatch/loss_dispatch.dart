import 'dart:math' as math;
import 'generator_model.dart';

/// Kron's transmission loss coefficients matrix B.
/// P_L = sum_i sum_j (P_i * B_ij * P_j) + sum_i (B_0i * P_i) + B_00
class LossCoefficients {
  const LossCoefficients({
    required this.bMatrix,
    this.b0Vector,
    this.b00 = 0.0,
  });

  /// Symmetric N x N matrix of quadratic loss coefficients (MW^-1)
  final List<List<double>> bMatrix;

  /// N x 1 vector of linear loss coefficients (dimensionless)
  final List<double>? b0Vector;

  /// Constant loss term (MW)
  final double b00;

  /// Computes transmission losses P_L (MW) given generator power vector [pVector].
  double calculateLoss(List<double> pVector) {
    final n = pVector.length;
    double loss = b00;

    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        loss += pVector[i] * bMatrix[i][j] * pVector[j];
      }
      if (b0Vector != null && i < b0Vector!.length) {
        loss += b0Vector![i] * pVector[i];
      }
    }
    return math.max(0.0, loss);
  }

  /// Incremental transmission loss: ∂P_L / ∂P_i = 2 * sum_j(B_ij * P_j) + B_0i
  double incrementalLoss(int i, List<double> pVector) {
    final n = pVector.length;
    double itl = (b0Vector != null && i < b0Vector!.length) ? b0Vector![i] : 0.0;
    for (var j = 0; j < n; j++) {
      itl += 2.0 * bMatrix[i][j] * pVector[j];
    }
    return itl;
  }

  /// Creates zero-loss coefficients for an N-unit system.
  factory LossCoefficients.zero(int n) {
    return LossCoefficients(
      bMatrix: List.generate(n, (_) => List.filled(n, 0.0)),
      b0Vector: List.filled(n, 0.0),
      b00: 0.0,
    );
  }
}

/// Single iteration record in the loss-included lambda-search.
class LossDispatchIteration {
  const LossDispatchIteration({
    required this.iteration,
    required this.lambda,
    required this.powers,
    required this.penaltyFactors,
    required this.incrementalLosses,
    required this.totalPower,
    required this.loss,
    required this.error,
  });

  final int iteration;
  final double lambda;
  final Map<String, double> powers;
  final Map<String, double> penaltyFactors;
  final Map<String, double> incrementalLosses;
  final double totalPower;
  final double loss;
  final double error;
}

/// Result of loss-included thermal economic dispatch.
class LossDispatchResult {
  const LossDispatchResult({
    required this.lambda,
    required this.powers,
    required this.totalPower,
    required this.demand,
    required this.transmissionLoss,
    required this.penaltyFactors,
    required this.totalCost,
    required this.converged,
    required this.iterations,
    required this.message,
  });

  final double lambda;
  final Map<String, double> powers;
  final double totalPower;
  final double demand;
  final double transmissionLoss;
  final Map<String, double> penaltyFactors;
  final double totalCost;
  final bool converged;
  final List<LossDispatchIteration> iterations;
  final String message;
}

abstract final class LossDispatchSolver {
  /// Solves loss-included economic dispatch using the secant / lambda-iteration method.
  static LossDispatchResult solve({
    required List<GeneratorUnit> units,
    required double demand,
    required LossCoefficients lossCoeffs,
    double tolerance = 1e-4,
    int maxIterations = 60,
  }) {
    final active = units.where((u) => u.isActive).toList();
    final n = active.length;

    if (n == 0) {
      return LossDispatchResult(
        lambda: 0.0,
        powers: const {},
        totalPower: 0.0,
        demand: demand,
        transmissionLoss: 0.0,
        penaltyFactors: const {},
        totalCost: 0.0,
        converged: false,
        iterations: const [],
        message: 'No active generators available.',
      );
    }

    // Initial lambda estimate from average incremental costs
    double lambdaLow = active.map((u) => u.icrAt(u.pMin)).reduce(math.min);
    double lambdaHigh = active.map((u) => u.icrAt(u.pMax)).reduce(math.max);
    double lambda = (lambdaLow + lambdaHigh) / 2.0;

    // Initial power guesses at midpoints
    var pVector = [for (final u in active) (u.pMin + u.pMax) / 2.0];
    final records = <LossDispatchIteration>[];

    double prevLambda = lambdaLow;
    double prevError = 1.0;
    bool hasPrev = false;

    for (var k = 1; k <= maxIterations; k++) {
      // Inner loop: Gauss-Seidel style update of generator powers for current lambda
      for (var inner = 0; inner < 8; inner++) {
        for (var i = 0; i < n; i++) {
          final u = active[i];
          final bii = lossCoeffs.bMatrix[i][i];
          final b0i = (lossCoeffs.b0Vector != null && i < lossCoeffs.b0Vector!.length)
              ? lossCoeffs.b0Vector![i]
              : 0.0;

          double crossSum = 0.0;
          for (var j = 0; j < n; j++) {
            if (j != i) {
              crossSum += lossCoeffs.bMatrix[i][j] * pVector[j];
            }
          }

          // Exact coordination equation rearrangement:
          // P_i = [ lambda*(1 - B_0i - 2*sum_{j!=i} B_ij*P_j) - beta_i ] / [ 2*(gamma_i + lambda*B_ii) ]
          final num = lambda * (1.0 - b0i - 2.0 * crossSum) - u.beta;
          final den = 2.0 * (u.gamma + lambda * bii);

          double pNew = den.abs() > 1e-12 ? num / den : u.pMin;

          // Enforce generator limits
          if (pNew < u.pMin) pNew = u.pMin;
          if (pNew > u.pMax) pNew = u.pMax;

          pVector[i] = pNew;
        }
      }

      // Calculate total generation and loss
      final totalGen = pVector.fold<double>(0.0, (acc, p) => acc + p);
      final pLoss = lossCoeffs.calculateLoss(pVector);
      final error = demand + pLoss - totalGen; // Power mismatch Er = P_D + P_L - sum(P_Gi)

      // Evaluate penalty factors and ITL
      final pMap = <String, double>{};
      final pfMap = <String, double>{};
      final itlMap = <String, double>{};

      for (var i = 0; i < n; i++) {
        final itl = lossCoeffs.incrementalLoss(i, pVector);
        final pf = (1.0 - itl).abs() > 1e-6 ? 1.0 / (1.0 - itl) : 1.0;
        pMap[active[i].id] = pVector[i];
        pfMap[active[i].id] = pf;
        itlMap[active[i].id] = itl;
      }

      records.add(LossDispatchIteration(
        iteration: k,
        lambda: lambda,
        powers: pMap,
        penaltyFactors: pfMap,
        incrementalLosses: itlMap,
        totalPower: totalGen,
        loss: pLoss,
        error: error,
      ));

      if (error.abs() <= tolerance) {
        // Converged!
        double cost = 0.0;
        for (var i = 0; i < n; i++) {
          cost += active[i].costAt(pVector[i]);
        }

        return LossDispatchResult(
          lambda: lambda,
          powers: pMap,
          totalPower: totalGen,
          demand: demand,
          transmissionLoss: pLoss,
          penaltyFactors: pfMap,
          totalCost: cost,
          converged: true,
          iterations: records,
          message: 'Converged after $k iterations with mismatch |Er| = ${error.abs().toStringAsExponential(2)} MW.',
        );
      }

      // Secant / Newton step for lambda
      double newLambda;
      if (!hasPrev || (error - prevError).abs() < 1e-9) {
        // Fixed step direction
        final step = error > 0 ? 0.05 * lambda.abs() + 0.1 : -0.05 * lambda.abs() - 0.1;
        newLambda = lambda + step;
      } else {
        // Secant update: lambda_new = lambda - error * (lambda - prevLambda) / (error - prevError)
        final dL = -error * (lambda - prevLambda) / (error - prevError);
        // Damping / step limiter for numerical robustness
        final maxStep = 0.5 * lambda.abs() + 1.0;
        final clampedStep = dL.clamp(-maxStep, maxStep);
        newLambda = lambda + clampedStep;
      }

      if (newLambda <= 0) newLambda = 0.1;

      prevLambda = lambda;
      prevError = error;
      hasPrev = true;
      lambda = newLambda;
    }

    // Max iterations exceeded
    double cost = 0.0;
    final pMap = <String, double>{};
    final pfMap = <String, double>{};
    for (var i = 0; i < n; i++) {
      cost += active[i].costAt(pVector[i]);
      pMap[active[i].id] = pVector[i];
      final itl = lossCoeffs.incrementalLoss(i, pVector);
      pfMap[active[i].id] = (1.0 - itl).abs() > 1e-6 ? 1.0 / (1.0 - itl) : 1.0;
    }

    return LossDispatchResult(
      lambda: lambda,
      powers: pMap,
      totalPower: pVector.fold<double>(0.0, (acc, p) => acc + p),
      demand: demand,
      transmissionLoss: lossCoeffs.calculateLoss(pVector),
      penaltyFactors: pfMap,
      totalCost: cost,
      converged: false,
      iterations: records,
      message: 'Did not converge within $maxIterations iterations (Final error: ${prevError.toStringAsFixed(4)} MW).',
    );
  }
}
