import 'generator_model.dart';

/// Single iteration step in iterative limit enforcement.
class DispatchIterationStep {
  const DispatchIterationStep({
    required this.iteration,
    required this.lambda,
    required this.unconstrainedGenerators,
    required this.clampedGenerators,
    required this.intermediatePowers,
    required this.notes,
  });

  final int iteration;
  final double lambda;
  final List<String> unconstrainedGenerators;
  final Map<String, double> clampedGenerators;
  final Map<String, double> intermediatePowers;
  final List<String> notes;
}

/// Result of lossless economic dispatch.
class LosslessDispatchResult {
  const LosslessDispatchResult({
    required this.lambda,
    required this.powers,
    required this.totalPower,
    required this.demand,
    required this.totalCost,
    required this.equalLoadingCost,
    required this.savings,
    required this.savingsPercent,
    required this.clampedUnits,
    required this.steps,
    required this.isFeasible,
    required this.message,
  });

  /// Optimal system incremental fuel cost ($/MWh)
  final double lambda;

  /// Power dispatch per generator (MW), keyed by generator id
  final Map<String, double> powers;

  /// Total power generated: sum(P_Gi) (MW)
  final double totalPower;

  /// System demand P_D (MW)
  final double demand;

  /// Total production cost with economic dispatch ($/h)
  final double totalCost;

  /// Total production cost under equal/proportional loading ($/h)
  final double equalLoadingCost;

  /// Cost savings: equalLoadingCost - totalCost ($/h)
  final double savings;

  /// Savings percentage (%)
  final double savingsPercent;

  /// Units clamped at limits: id -> clamped power (MW)
  final Map<String, double> clampedUnits;

  /// Step-by-step progress through limit enforcement
  final List<DispatchIterationStep> steps;

  /// Whether demand is within aggregate generation capacity
  final bool isFeasible;

  final String message;
}

abstract final class LosslessDispatchSolver {
  /// Solves lossless economic dispatch for active units given system demand [demand] (MW).
  ///
  /// Enforces limits [enforceLimits]: if any unit violates P_min or P_max,
  /// it is fixed at that boundary, subtracted from remaining demand, and the
  /// remaining unconstrained units are iteratively re-dispatched.
  static LosslessDispatchResult solve({
    required List<GeneratorUnit> units,
    required double demand,
    bool enforceLimits = true,
  }) {
    final active = units.where((u) => u.isActive).toList();
    if (active.isEmpty) {
      return LosslessDispatchResult(
        lambda: 0.0,
        powers: const {},
        totalPower: 0.0,
        demand: demand,
        totalCost: 0.0,
        equalLoadingCost: 0.0,
        savings: 0.0,
        savingsPercent: 0.0,
        clampedUnits: const {},
        steps: const [],
        isFeasible: false,
        message: 'No active generators available.',
      );
    }

    final totalMin = active.fold<double>(0.0, (acc, u) => acc + u.pMin);
    final totalMax = active.fold<double>(0.0, (acc, u) => acc + u.pMax);

    if (demand < totalMin) {
      return _buildInfeasibleResult(
        active,
        demand,
        'Demand (${demand.toStringAsFixed(1)} MW) is less than minimum generation capacity (${totalMin.toStringAsFixed(1)} MW).',
      );
    }
    if (demand > totalMax) {
      return _buildInfeasibleResult(
        active,
        demand,
        'Demand (${demand.toStringAsFixed(1)} MW) exceeds maximum generation capacity (${totalMax.toStringAsFixed(1)} MW).',
      );
    }

    final unconstrained = List<GeneratorUnit>.from(active);
    final clamped = <String, double>{};
    final steps = <DispatchIterationStep>[];
    double currentDemand = demand;
    double lambda = 0.0;
    final finalPowers = <String, double>{};

    var iteration = 1;
    while (true) {
      if (unconstrained.isEmpty) {
        break;
      }

      // Compute lambda for unconstrained units:
      // lambda = (P_D' + sum(beta_i / (2*gamma_i))) / sum(1 / (2*gamma_i))
      double sumInv2Gamma = 0.0;
      double sumBetaOver2Gamma = 0.0;

      for (final u in unconstrained) {
        if (u.gamma > 0) {
          final inv2g = 1.0 / (2.0 * u.gamma);
          sumInv2Gamma += inv2g;
          sumBetaOver2Gamma += u.beta * inv2g;
        } else {
          // linear unit fallback with small epsilon
          final inv2g = 1.0 / 0.0001;
          sumInv2Gamma += inv2g;
          sumBetaOver2Gamma += u.beta * inv2g;
        }
      }

      lambda = (currentDemand + sumBetaOver2Gamma) / sumInv2Gamma;

      final trialPowers = <String, double>{};
      final newlyViolated = <GeneratorUnit>[];
      final notes = <String>[];

      for (final u in unconstrained) {
        final p = (lambda - u.beta) / (2.0 * (u.gamma > 0 ? u.gamma : 0.00005));
        trialPowers[u.id] = p;

        if (enforceLimits) {
          if (p < u.pMin) {
            newlyViolated.add(u);
            notes.add('${u.name}: computed ${p.toStringAsFixed(2)} MW < P_min (${u.pMin} MW) → clamp at P_min');
          } else if (p > u.pMax) {
            newlyViolated.add(u);
            notes.add('${u.name}: computed ${p.toStringAsFixed(2)} MW > P_max (${u.pMax} MW) → clamp at P_max');
          }
        }
      }

      steps.add(DispatchIterationStep(
        iteration: iteration,
        lambda: lambda,
        unconstrainedGenerators: unconstrained.map((u) => u.name).toList(),
        clampedGenerators: Map<String, double>.from(clamped),
        intermediatePowers: Map<String, double>.from(trialPowers),
        notes: notes,
      ));

      if (!enforceLimits || newlyViolated.isEmpty) {
        // Optimal dispatch achieved
        for (final u in unconstrained) {
          finalPowers[u.id] = trialPowers[u.id]!;
        }
        break;
      }

      // Clamp newly violated units and adjust remaining demand
      for (final v in newlyViolated) {
        final pTrial = trialPowers[v.id]!;
        final clampVal = pTrial < v.pMin ? v.pMin : v.pMax;
        clamped[v.id] = clampVal;
        finalPowers[v.id] = clampVal;
        currentDemand -= clampVal;
        unconstrained.removeWhere((u) => u.id == v.id);
      }

      iteration++;
      if (iteration > active.length + 2) {
        // Guard against cycles
        break;
      }
    }

    // Merge clamped and final powers
    clamped.forEach((id, p) {
      finalPowers[id] = p;
    });

    // Calculate costs
    double totalCost = 0.0;
    double totalPower = 0.0;
    for (final u in active) {
      final p = finalPowers[u.id] ?? u.pMin;
      totalPower += p;
      totalCost += u.costAt(p);
    }

    // Cost comparison with equal/proportional loading allocation
    final equalPowers = _calculateEqualAllocation(active, demand);
    double equalCost = 0.0;
    for (final u in active) {
      equalCost += u.costAt(equalPowers[u.id] ?? 0.0);
    }

    final savings = equalCost - totalCost;
    final savingsPercent = equalCost > 0 ? (savings / equalCost) * 100.0 : 0.0;

    return LosslessDispatchResult(
      lambda: lambda,
      powers: finalPowers,
      totalPower: totalPower,
      demand: demand,
      totalCost: totalCost,
      equalLoadingCost: equalCost,
      savings: savings > 0 ? savings : 0.0,
      savingsPercent: savingsPercent > 0 ? savingsPercent : 0.0,
      clampedUnits: clamped,
      steps: steps,
      isFeasible: true,
      message: 'Optimal dispatch found across ${active.length} units with equal incremental cost λ = ${lambda.toStringAsFixed(4)} \$/MWh.',
    );
  }

  /// Allocates demand equally among units, respecting individual P_min/P_max limits.
  static Map<String, double> _calculateEqualAllocation(
    List<GeneratorUnit> units,
    double demand,
  ) {
    final allocation = <String, double>{};
    final n = units.length;
    final equalP = demand / n;

    // Check if simple equal sharing satisfies all bounds
    bool simpleOk = true;
    for (final u in units) {
      if (equalP < u.pMin || equalP > u.pMax) {
        simpleOk = false;
        break;
      }
    }

    if (simpleOk) {
      for (final u in units) {
        allocation[u.id] = equalP;
      }
      return allocation;
    }

    // Capacity-proportional allocation respecting bounds
    final minSum = units.fold<double>(0.0, (acc, u) => acc + u.pMin);
    final maxSum = units.fold<double>(0.0, (acc, u) => acc + u.pMax);
    final range = maxSum - minSum;

    if (range > 0) {
      final ratio = (demand - minSum) / range;
      for (final u in units) {
        final p = u.pMin + ratio * (u.pMax - u.pMin);
        allocation[u.id] = p;
      }
    } else {
      for (final u in units) {
        allocation[u.id] = u.pMin;
      }
    }

    return allocation;
  }

  static LosslessDispatchResult _buildInfeasibleResult(
    List<GeneratorUnit> units,
    double demand,
    String message,
  ) {
    final powers = <String, double>{};
    for (final u in units) {
      powers[u.id] = u.pMin;
    }
    return LosslessDispatchResult(
      lambda: 0.0,
      powers: powers,
      totalPower: units.fold<double>(0.0, (acc, u) => acc + u.pMin),
      demand: demand,
      totalCost: 0.0,
      equalLoadingCost: 0.0,
      savings: 0.0,
      savingsPercent: 0.0,
      clampedUnits: const {},
      steps: const [],
      isFeasible: false,
      message: message,
    );
  }
}
